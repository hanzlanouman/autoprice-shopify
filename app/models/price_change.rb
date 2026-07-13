# Append-only audit trail for material pricing decisions. Applied changes,
# rejected/failed recommendations, restorations, and recommendation-level skips
# are retained; routine pre-eligibility skips remain in bounded run statistics.
class PriceChange < ApplicationRecord
  STATUSES = %w[applied rejected failed skipped].freeze
  ACTIONS = %w[increase restore].freeze
  SOURCES = %w[ai fallback system].freeze

  belongs_to :pricing_run
  belongs_to :product, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :action, inclusion: { in: ACTIONS }
  validates :source, inclusion: { in: SOURCES }
  validates :shopify_variant_gid, presence: true
  validates :shopify_variant_gid, uniqueness: { scope: :pricing_run_id }

  validate :applied_price_is_sane

  before_update { raise ActiveRecord::ReadOnlyRecord, "price_changes are append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "price_changes are append-only" }

  scope :recent, -> { order(created_at: :desc) }

  private

  def applied_price_is_sane
    return unless status == "applied"

    errors.add(:new_price, "must be present for an applied change") if new_price.nil?
    errors.add(:old_price, "must be present for an applied change") if old_price.nil?
    return if new_price.nil? || old_price.nil?

    if action == "increase" && new_price < old_price
      errors.add(:new_price, "cannot be below the previous price for an increase")
    elsif action == "restore" && new_price > old_price
      errors.add(:new_price, "cannot exceed the previous price for a restore")
    end
  end
end
