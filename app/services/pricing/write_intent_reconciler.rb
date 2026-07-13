module Pricing
  # Resolves price writes whose outcome became uncertain because the worker
  # stopped or lost the Shopify response. This runs against freshly fetched
  # Shopify data before guard state is read for a new pricing decision.
  class WriteIntentReconciler
    def call(product_nodes)
      live_prices = extract_live_prices(product_nodes)
      return 0 if live_prices.empty?

      intents = PriceWriteIntent.unresolved.where(shopify_variant_gid: live_prices.keys).includes(:product, :pricing_run)
      intents.count { |intent| reconcile(intent, live_prices.fetch(intent.shopify_variant_gid)) }
    end

    private

    def extract_live_prices(nodes)
      nodes.each_with_object({}) do |product, prices|
        (product.dig("variants", "nodes") || []).each do |variant|
          price = Money.parse(variant["price"])
          prices[variant["id"]] = price if price
        end
      end
    end

    def reconcile(intent, live_price)
      if live_price == intent.target_price
        finalize(intent, status: "applied", resolution: "confirmed_from_live_price", update_guard: true)
      elsif live_price == intent.expected_old_price
        finalize(intent, status: "failed", resolution: "shopify_write_not_applied")
      else
        finalize(intent, status: "failed", resolution: "live_price_changed_externally", intent_status: "superseded")
      end
      true
    rescue ActiveRecord::RecordNotUnique
      # A normal completion raced this recovery pass. The unique history key
      # makes the operation idempotent, so the other writer won safely.
      false
    end

    def finalize(intent, status:, resolution:, intent_status: status, update_guard: false)
      PriceWriteIntent.transaction do
        intent.lock!
        return unless intent.status == "pending"

        update_product_guard(intent) if update_guard
        PriceChange.insert_all(
          [ intent.history_attributes(status: status, rejection_reason: status == "failed" ? resolution : nil) ],
          unique_by: :index_price_changes_on_run_and_variant
        )
        intent.resolve!(status: intent_status, reason: resolution)
        update_run_stats(intent.pricing_run, resolved_as: status)
      end
    end

    def update_product_guard(intent)
      product = intent.product
      return unless product

      product.lock!
      variants = product.variant_snapshots.map do |variant|
        next variant unless variant[:gid] == intent.shopify_variant_gid

        GuardState.apply(
          variant,
          action: intent.action,
          old_price: intent.expected_old_price,
          new_price: intent.target_price,
          inventory_level: intent.inventory_level,
          at: intent.created_at
        )
      end
      product.update!(variants: variants)
    end

    def update_run_stats(run, resolved_as:)
      run.lock!
      stats = run.stats.deep_dup
      pending = stats.fetch("pending_reconciliation", 0).to_i
      stats["pending_reconciliation"] = [ pending - 1, 0 ].max
      stats[resolved_as] = stats.fetch(resolved_as, 0).to_i + 1
      run.update!(stats: stats)
    end
  end
end
