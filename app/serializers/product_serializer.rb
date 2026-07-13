# Single source of the product JSON shape (docs/ARCHITECTURE.md). Eligibility is computed
# via Pricing::Bounds when settings are supplied, so the dashboard and the
# pricing pipeline agree on what "eligible" means (D2). Phase 1 passes no
# settings and eligibility is reported as not-yet-evaluated.
class ProductSerializer
  def initialize(product, settings: nil, latest_changes: {}, latest_applied_changes: {})
    @product = product
    @settings = settings
    @latest_changes = latest_changes
    @latest_applied_changes = latest_applied_changes
  end

  def as_json(*)
    {
      id: @product.id,
      shopify_gid: @product.shopify_gid,
      title: @product.title,
      product_type: @product.product_type,
      vendor: @product.vendor,
      status: @product.status,
      synced_at: @product.synced_at&.iso8601,
      variants: @product.variant_snapshots.map { |v| variant_json(v) }
    }
  end

  private

  def variant_json(variant)
    eligibility = evaluate(variant)
    latest = @latest_changes[variant[:gid]]
    latest_applied = @latest_applied_changes[variant[:gid]]
    {
      gid: variant[:gid],
      title: variant[:title],
      price: variant[:price],
      inventory_quantity: variant[:inventory_quantity],
      tracked: variant[:tracked],
      eligible: eligibility[:eligible],
      eligibility_reason: eligibility[:reason],
      original_price: variant[:original_price],
      base_price: variant[:original_price].presence || variant[:price],
      maximum_price: eligibility[:ceiling],
      previous_price: previous_price(variant, latest_applied),
      last_adjusted_at: variant[:last_adjusted_at],
      latest_recommended_price: latest && Money.format(latest.raw_recommended_price || latest.new_price),
      latest_old_price: latest && Money.format(latest.old_price),
      latest_new_price: latest && Money.format(latest.new_price),
      latest_reason: latest && (latest.ai_reason.presence || latest.rejection_reason),
      last_change_at: latest&.created_at&.iso8601,
      latest_source: latest&.source,
      latest_status: latest&.status
    }
  end

  # "Previous" means the live price immediately before the most recent
  # confirmed automated write. Hide stale history when Shopify was edited
  # externally and the cached live price no longer matches that write.
  def previous_price(variant, latest_applied)
    return unless latest_applied
    return unless Money.parse(variant[:price]) == latest_applied.new_price

    Money.format(latest_applied.old_price)
  end

  # Same Pricing::Bounds the pipeline uses, so the badge and the pricing run
  # agree on eligibility (D2).
  def evaluate(variant)
    return { eligible: false, reason: "not_evaluated", ceiling: nil } if @settings.nil?

    snapshot = Value::VariantSnapshot.from_cache(variant, gift_card: @product.gift_card)
    bounds = Pricing::Bounds.new(variant: snapshot, settings: @settings)
    {
      eligible: bounds.eligible?,
      reason: bounds.reason.to_s,
      ceiling: Money.format(bounds.ceiling)
    }
  end
end
