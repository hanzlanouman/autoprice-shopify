# Local cache of Shopify products. Shopify remains the source
# of truth; this exists for fast dashboard reads, the re-adjustment guard, and
# original-price memory. It is never an input to pricing bounds.
class Product < ApplicationRecord
  has_many :price_changes, dependent: :nullify
  has_many :price_write_intents, dependent: :nullify

  validates :shopify_gid, presence: true, uniqueness: true

  scope :active, -> { where(status: "active", stale_at: nil) }
  scope :stale, -> { where.not(stale_at: nil) }

  # Convenience readers over the variants JSON. Each element is a Hash with
  # string keys as stored (see CreateProducts migration).
  def variant_snapshots
    (variants || []).map { |v| v.with_indifferent_access }
  end
end
