# Durable record created before a Shopify price mutation. It closes the
# unavoidable external-write/database-write gap: if a worker dies after Shopify
# accepts a price but before local state is committed, the next product fetch
# reconciles this intent against the live price before any new recommendation.
class PriceWriteIntent < ApplicationRecord
  STATUSES = %w[pending applied failed superseded].freeze
  ACTIONS = %w[increase restore].freeze
  SOURCES = %w[ai fallback system].freeze

  belongs_to :pricing_run
  belongs_to :product, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :action, inclusion: { in: ACTIONS }
  validates :source, inclusion: { in: SOURCES }
  validates :product_gid, :shopify_variant_gid, presence: true
  validates :expected_old_price, :target_price, numericality: { greater_than_or_equal_to: 0 }

  scope :unresolved, -> { where(status: "pending") }

  def resolve!(status:, reason: nil)
    update!(status: status, resolution_reason: reason, resolved_at: Time.current)
  end

  def history_attributes(status:, rejection_reason: nil)
    {
      pricing_run_id: pricing_run_id,
      product_id: product_id,
      shopify_variant_gid: shopify_variant_gid,
      variant_title: variant_title,
      status: status,
      action: action,
      source: source,
      old_price: expected_old_price,
      new_price: status == "applied" ? target_price : nil,
      raw_recommended_price: action == "increase" ? target_price : nil,
      inventory_level: inventory_level,
      ai_reason: reason,
      rejection_reason: rejection_reason,
      created_at: Time.current
    }
  end
end
