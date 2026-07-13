module Pricing
  # Stage 5: writes accepted prices to Shopify (one bulk mutation per product),
  # then mirrors the change plus guard state into the local cache. Shopify is
  # written FIRST; a row becomes "applied" only if the write succeeds (D5). A
  # single product's failure marks just its variants failed and never aborts the
  # run. This is the only writer of variant guard state.
  class PriceApplier
    MAX_VARIANTS_PER_MUTATION = 250

    def initialize(client:)
      @client = client
    end

    # A durable intent is inserted before each external mutation. Confirmed
    # writes update guard state, history, and intent status in one DB
    # transaction. Transport failures remain pending for live reconciliation.
    def call(run, pending)
      pending.group_by(&:product_gid).flat_map do |product_gid, changes|
        changes.each_slice(MAX_VARIANTS_PER_MUTATION).flat_map do |chunk|
          apply_product(run, product_gid, chunk)
        end
      end
    end

    private

    def apply_product(run, product_gid, changes)
      intents = create_intents(run, changes)
      variants = changes.map { |c| { id: c.variant_gid, price: c.new_price } }
      verify_current_prices!(changes) if @client.respond_to?(:fetch_variant_prices)
      response = @client.update_variant_prices(product_gid, variants)
      verify_response!(response, changes)
      finalize_confirmed(product_gid, changes, intents)
      changes.map { |c| c.with(status: "applied") }
    rescue Shopify::Unavailable, Shopify::RateLimited => e
      # The request may have reached Shopify even though its response did not
      # reach us. Leave the intent pending; the next fresh fetch decides the
      # outcome without risking a duplicate increase.
      reason = "shopify_outcome_unknown:#{e.message}".truncate(200)
      changes.map { |c| c.with(status: "reconciling", rejection_reason: reason) }
    rescue Shopify::Error => e
      reason = "shopify_error:#{e.message}".truncate(200)
      resolve_failed_intents(intents, reason) if intents
      changes.map { |c| c.with(status: "failed", rejection_reason: reason) }
    end

    def create_intents(run, changes)
      changes.map do |change|
        PriceWriteIntent.create!(
          pricing_run: run,
          product_id: change.product_id,
          product_gid: change.product_gid,
          shopify_variant_gid: change.variant_gid,
          variant_title: change.variant_title,
          action: change.action,
          source: change.source,
          expected_old_price: change.old_price,
          target_price: change.new_price,
          inventory_level: change.inventory_level,
          reason: change.ai_reason
        )
      end
    end

    def verify_response!(response, changes)
      returned = Array(response).index_by { |variant| variant["id"] || variant[:id] }
      changes.each do |change|
        actual = Money.parse(returned.dig(change.variant_gid, "price") || returned.dig(change.variant_gid, :price))
        next if actual == Money.round(change.new_price)

        raise Shopify::Unavailable, "Shopify did not confirm variant #{change.variant_gid} at the requested price"
      end
    end

    def verify_current_prices!(changes)
      current = @client.fetch_variant_prices(changes.map(&:variant_gid))
      prices = Array(current).to_h do |variant|
        [ variant["id"] || variant[:id], Money.parse(variant["price"] || variant[:price]) ]
      end
      changed = changes.find { |change| prices[change.variant_gid] != Money.round(change.old_price) }
      return unless changed

      raise Shopify::ConcurrentModification,
            "variant #{changed.variant_gid} changed after the pricing run fetched it"
    end

    def finalize_confirmed(product_gid, changes, intents)
      PriceWriteIntent.transaction do
        update_cache(product_gid, changes)
        rows = intents.map { |intent| intent.history_attributes(status: "applied") }
        PriceChange.insert_all(rows, unique_by: :index_price_changes_on_run_and_variant)
        PriceWriteIntent.where(id: intents.map(&:id)).update_all(
          status: "applied",
          resolution_reason: "confirmed_by_mutation_response",
          resolved_at: Time.current,
          updated_at: Time.current
        )
      end
    end

    def resolve_failed_intents(intents, reason)
      PriceWriteIntent.where(id: intents.map(&:id)).update_all(
        status: "failed",
        resolution_reason: reason,
        resolved_at: Time.current,
        updated_at: Time.current
      )
    end

    def update_cache(product_gid, changes)
      product = Product.lock.find_by(shopify_gid: product_gid)
      return unless product

      by_gid = changes.index_by(&:variant_gid)
      now = Time.current.iso8601
      updated = product.variant_snapshots.map do |v|
        change = by_gid[v[:gid]]
        change ? GuardState.apply(
          v,
          action: change.action,
          old_price: change.old_price,
          new_price: change.new_price,
          inventory_level: change.inventory_level,
          at: Time.iso8601(now)
        ) : v
      end
      product.update!(variants: updated)
    end
  end
end
