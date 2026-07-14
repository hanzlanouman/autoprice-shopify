module Value
  # Immutable per-variant view used across the pricing pipeline. Combines live
  # Shopify data (price, inventory, tracked) with cached guard state
  # (original_price, last_written_price, adjustment history) so downstream
  # stages stay pure — they never touch the database.
  VariantSnapshot = Data.define(
    :gid,
    :title,
    :price,                        # BigDecimal — current Shopify price
    :inventory_quantity,          # Integer or nil (untracked)
    :tracked,                     # Boolean
    :gift_card,                   # Boolean
    :original_price,              # BigDecimal or nil — percentage-cap base
    :last_written_price,          # BigDecimal or nil — last price WE wrote (A12)
    :last_adjusted_at,            # Time or nil
    :inventory_at_last_adjustment # Integer or nil
  ) do
    def adjusted?
      !last_adjusted_at.nil?
    end

    def inventory
      inventory_quantity.to_i
    end

    # Rebuilds a snapshot from a cached variant hash (Product#variant_snapshots)
    # so the serializer and pipeline can evaluate bounds without a Shopify fetch.
    def self.from_cache(hash, gift_card: false)
      new(
        gid: hash[:gid],
        title: hash[:title].to_s,
        price: Money.parse(hash[:price]) || BigDecimal(0),
        inventory_quantity: hash[:inventory_quantity],
        tracked: hash[:tracked] == true,
        gift_card: gift_card,
        original_price: Money.parse(hash[:original_price]),
        last_written_price: Money.parse(hash[:last_written_price]),
        last_adjusted_at: hash[:last_adjusted_at].present? ? Time.zone.parse(hash[:last_adjusted_at].to_s) : nil,
        inventory_at_last_adjustment: hash[:inventory_at_last_adjustment]
      )
    end
  end
end
