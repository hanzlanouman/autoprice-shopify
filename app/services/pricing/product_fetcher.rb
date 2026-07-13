module Pricing
  # Stage 1 of the pipeline: fetch live products from Shopify, merge cached guard
  # state, upsert the local cache, and return immutable snapshots. Detects
  # merchant manual edits and re-bases them (A12) so we never fight the merchant.
  class ProductFetcher
    def initialize(client: Shopify::Client.build, reconciler: WriteIntentReconciler.new)
      @client = client
      @reconciler = reconciler
    end

    # Returns Array<Value::ProductSnapshot>.
    def call
      nodes = @client.fetch_products
      @reconciler&.call(nodes)

      Product.transaction do
        cached = cached_guard_state(nodes.map { |n| n["id"] })
        snapshots = nodes.map { |node| build_snapshot(node, cached) }
        persist(snapshots)
        snapshots
      end
    end

    private

    # gid => { variant_gid => guard hash } from the existing cache.
    def cached_guard_state(product_gids)
      Product.where(shopify_gid: product_gids).order(:id).lock.each_with_object({}) do |product, acc|
        acc[product.shopify_gid] = product.variant_snapshots.index_by { |v| v[:gid] }
      end
    end

    def build_snapshot(node, cached)
      guard_for_product = cached[node["id"]] || {}

      variants = (node.dig("variants", "nodes") || []).map do |vnode|
        build_variant(vnode, node, guard_for_product[vnode["id"]])
      end

      Value::ProductSnapshot.new(
        gid: node["id"],
        title: node["title"].to_s,
        product_type: node["productType"],
        vendor: node["vendor"],
        status: (node["status"] || "ACTIVE").downcase,
        gift_card: node["isGiftCard"] == true,
        variants: variants
      )
    end

    def build_variant(vnode, product_node, guard)
      guard ||= {}
      live_price = Money.parse(vnode["price"])
      unless vnode["id"].present? && live_price
        raise Shopify::Unavailable, "Shopify returned a variant with a missing id or invalid price"
      end
      original_price = Money.parse(guard[:original_price])
      last_written = Money.parse(guard[:last_written_price])
      last_adjusted_at = guard[:last_adjusted_at]
      inventory_at_last = guard[:inventory_at_last_adjustment]

      # A12: a live price that differs from the last price WE wrote means the
      # merchant (or another app) changed it. Re-base around their value and
      # forget our adjustment state.
      if last_written && live_price && live_price != last_written
        original_price = live_price
        last_written = nil
        last_adjusted_at = nil
        inventory_at_last = nil
      end

      Value::VariantSnapshot.new(
        gid: vnode["id"],
        title: vnode["title"].to_s,
        price: live_price,
        inventory_quantity: vnode["inventoryQuantity"],
        tracked: vnode.dig("inventoryItem", "tracked") == true,
        gift_card: product_node["isGiftCard"] == true,
        original_price: original_price,
        last_written_price: last_written,
        last_adjusted_at: last_adjusted_at.present? ? last_adjusted_at.to_time : nil,
        inventory_at_last_adjustment: inventory_at_last
      )
    end

    def persist(snapshots)
      now = Time.current
      rows = snapshots.map do |s|
        {
          shopify_gid: s.gid,
          title: s.title,
          product_type: s.product_type,
          vendor: s.vendor,
          status: s.status,
          gift_card: s.gift_card,
          synced_at: now,
          stale_at: nil,
          variants: s.variants.map { |v| serialize_variant(v) },
          created_at: now,
          updated_at: now
        }
      end
      if rows.any?
        # updated_at is managed by Rails automatically; listing it here would
        # assign it twice in the SET clause.
        Product.upsert_all(
          rows,
          unique_by: :shopify_gid,
          update_only: %i[title product_type vendor status gift_card synced_at stale_at variants]
        )
      end

      mark_missing_stale(snapshots.map(&:gid), at: now)
    end

    # fetch_products only returns after every product and variant page has been
    # read. Therefore this runs only for a complete sync; exceptions leave the
    # prior catalogue visibility untouched. History remains associated with the
    # soft-stale product row.
    def mark_missing_stale(fetched_gids, at:)
      scope = Product.where(stale_at: nil)
      scope = scope.where.not(shopify_gid: fetched_gids) if fetched_gids.any?
      scope.update_all(stale_at: at, updated_at: at)
    end

    def serialize_variant(v)
      {
        gid: v.gid,
        title: v.title,
        price: Money.format(v.price),
        inventory_quantity: v.inventory_quantity,
        tracked: v.tracked,
        original_price: Money.format(v.original_price),
        last_written_price: Money.format(v.last_written_price),
        last_adjusted_at: v.last_adjusted_at&.iso8601,
        inventory_at_last_adjustment: v.inventory_at_last_adjustment
      }
    end
  end
end
