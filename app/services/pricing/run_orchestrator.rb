module Pricing
  # Composes the pipeline for one run: fetch → filter → recommend → validate →
  # apply → record. Deterministic code owns correctness; the
  # recommender only proposes prices inside bounds it is told. Settings are read
  # once so the run is internally consistent (D12).
  class RunOrchestrator
    def initialize(client: Shopify::Client.build, recommender: Recommender.for_environment)
      @client = client
      @recommender = recommender
    end

    def call(run)
      settings = Setting.instance
      snapshots = ProductFetcher.new(client: @client).call
      run.touch
      product_ids = product_id_map(snapshots)

      partition = EligibilityFilter.new(settings).call(snapshots)
      recs = recommend(partition.eligible, settings)
      run.touch

      increases = partition.eligible.map { |item| plan_increase(item, recs, product_ids) }
      restores = partition.restorable.map { |item| plan_restore(item, product_ids, settings) }
      skips = partition.skipped.map { |item| plan_skip(item, product_ids) }

      pending, terminal = (increases + restores).partition(&:pending?)
      if run.trigger == "scheduled" && !Setting.instance.reload.auto_pricing_enabled?
        cancelled = pending.map do |change|
          change.with(status: "skipped", new_price: nil, rejection_reason: "auto_pricing_disabled")
        end
        pending = []
        terminal += cancelled
      end
      applied = PriceApplier.new(client: @client).call(run, pending)
      run.touch

      all_changes = applied + terminal + skips
      # Confirmed Shopify writes are recorded atomically with guard state by
      # PriceApplier. Routine deterministic exclusions are counted in run stats
      # but intentionally not copied into the unbounded history table.
      recordable = terminal + applied.select { |change| change.status == "failed" }
      HistoryRecorder.new.call(run, recordable)

      stats = build_stats(snapshots, partition, all_changes, settings)
      run.complete!(stats)
      Rails.logger.info("[pricing_run] run=#{run.id} #{stats.to_json}")
      run
    end

    private

    # Runs the primary recommender, then — if the merchant enabled fallback
    # pricing — fills any variants Gemini couldn't answer with the deterministic
    # formula (labeled "fallback"). Otherwise those variants are left to be
    # skipped by the validator.
    def recommend(eligible, settings)
      primary = @recommender.recommend(eligible, settings)
      recs = primary.index_by(&:variant_gid)
      unavailable_count = primary.count { |rec| rec.error == :gemini_unavailable }
      fallback_used = false

      if settings.fallback_pricing_enabled
        unavailable = eligible.select { |item| recs[item.variant.gid]&.error == :gemini_unavailable }
        if unavailable.any?
          Recommender::Deterministic.new(source: "fallback").recommend(unavailable, settings).each do |rec|
            recs[rec.variant_gid] = rec
          end
          fallback_used = true
        end
      end

      @recommendation_meta = {
        recommendation_source: normalize_source(@recommender.source_label),
        fallback_used: fallback_used,
        ai_unavailable: unavailable_count.positive?,
        ai_unavailable_count: unavailable_count,
        recommendation_count: recs.size
      }
      if @recommender.respond_to?(:last_metrics) && @recommender.last_metrics.present?
        @recommendation_meta.merge!(@recommender.last_metrics)
      end

      recs
    end

    def product_id_map(snapshots)
      Product.where(shopify_gid: snapshots.map(&:gid)).pluck(:shopify_gid, :id).to_h
    end

    def plan_increase(item, recs, product_ids)
      variant = item.variant
      rec = recs[variant.gid] ||
            Value::Recommendation.failed(variant_gid: variant.gid, error: :no_recommendation, source: @recommender.source_label)
      outcome = PriceValidator.new(item.bounds).call(rec)

      keep_reason = outcome.status == :pending || outcome.rejection_reason == "no_change_recommended"
      Value::PlannedChange.new(
        product_gid: item.product.gid,
        product_id: product_ids[item.product.gid],
        variant_gid: variant.gid,
        variant_title: variant.title,
        status: outcome.status,
        action: "increase",
        source: rec.source,
        old_price: variant.price,
        new_price: outcome.new_price,
        raw_recommended_price: rec.price,
        inventory_level: variant.inventory,
        ai_reason: keep_reason ? rec.reason : nil,
        rejection_reason: outcome.rejection_reason
      )
    end

    def plan_skip(item, product_ids)
      variant = item.variant
      Value::PlannedChange.new(
        product_gid: item.product.gid,
        product_id: product_ids[item.product.gid],
        variant_gid: variant.gid,
        variant_title: variant.title,
        status: "skipped",
        action: "increase",
        source: "system",
        old_price: variant.price,
        new_price: nil,
        raw_recommended_price: nil,
        inventory_level: variant.inventory_quantity,
        ai_reason: nil,
        rejection_reason: item.reason
      )
    end

    def plan_restore(item, product_ids, settings)
      variant = item.variant
      Value::PlannedChange.new(
        product_gid: item.product.gid,
        product_id: product_ids[item.product.gid],
        variant_gid: variant.gid,
        variant_title: variant.title,
        status: :pending,
        action: "restore",
        source: "system",
        old_price: variant.price,
        new_price: variant.original_price,
        raw_recommended_price: variant.original_price,
        inventory_level: variant.inventory,
        ai_reason: "Inventory #{variant.inventory} is above threshold #{settings.inventory_threshold}; restored the app-owned price to base #{Money.format(variant.original_price)}.",
        rejection_reason: nil
      )
    end

    def build_stats(snapshots, partition, all_changes, settings)
      counts = all_changes.group_by { |c| c.status.to_s }.transform_values(&:size)
      {
        products_fetched: snapshots.size,
        eligible: partition.eligible.size,
        restorable: partition.restorable.size,
        applied: counts.fetch("applied", 0),
        rejected: counts.fetch("rejected", 0),
        failed: counts.fetch("failed", 0),
        skipped: counts.fetch("skipped", 0),
        pending_reconciliation: counts.fetch("reconciling", 0),
        source: normalize_source(@recommender.source_label),
        settings: {
          inventory_threshold: settings.inventory_threshold,
          max_price_percentage: Money.format(settings.max_price_percentage),
          review_frequency: settings.review_frequency,
          ai_behavior_prompt: settings.ai_behavior_prompt,
          fallback_pricing_enabled: settings.fallback_pricing_enabled,
          price_restoration_enabled: settings.price_restoration_enabled
        }
      }.merge(@recommendation_meta || {})
    end

    def normalize_source(source)
      source == "gemini" ? "ai" : source
    end
  end
end
