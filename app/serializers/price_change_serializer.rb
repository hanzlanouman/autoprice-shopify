# Single source of the price-change JSON shape, shared by the history list and
# run detail. Money is serialized as strings.
class PriceChangeSerializer
  def initialize(price_change)
    @price_change = price_change
  end

  def as_json(*)
    pc = @price_change
    {
      id: pc.id,
      pricing_run_id: pc.pricing_run_id,
      product_title: pc.product&.title,
      variant_title: pc.variant_title,
      shopify_variant_gid: pc.shopify_variant_gid,
      status: pc.status,
      action: pc.action,
      source: pc.source,
      old_price: Money.format(pc.old_price),
      new_price: Money.format(pc.new_price),
      raw_recommended_price: Money.format(pc.raw_recommended_price),
      inventory_level: pc.inventory_level,
      ai_reason: pc.ai_reason,
      rejection_reason: pc.rejection_reason,
      created_at: pc.created_at.iso8601
    }
  end
end
