module Pricing
  # Stage 2: partitions variants into increases, opt-in base-price restores,
  # and deterministic skips. Increase eligibility comes from Pricing::Bounds.
  class EligibilityFilter
    Eligible = Data.define(:product, :variant, :bounds)
    Restorable = Data.define(:product, :variant)
    Skipped = Data.define(:product, :variant, :reason)
    Partition = Data.define(:eligible, :restorable, :skipped)

    def initialize(settings)
      @settings = settings
    end

    def call(product_snapshots)
      eligible = []
      restorable = []
      skipped = []

      product_snapshots.each do |product|
        product.variants.each do |variant|
          bounds = Bounds.new(variant: variant, settings: @settings)
          if restorable?(variant)
            restorable << Restorable.new(product: product, variant: variant)
          elsif bounds.eligible?
            eligible << Eligible.new(product: product, variant: variant, bounds: bounds)
          else
            skipped << Skipped.new(product: product, variant: variant, reason: bounds.reason.to_s)
          end
        end
      end

      Partition.new(eligible: eligible, restorable: restorable, skipped: skipped)
    end

    private

    # Restoration is deliberately stricter than ordinary eligibility. It only
    # reverses an app-owned increase after inventory moves above the threshold.
    # ProductFetcher clears adjustment state when a merchant edits the price,
    # so an external price can never be mistaken for an app-owned increase.
    def restorable?(variant)
      @settings.price_restoration_enabled? &&
        !variant.gift_card && variant.tracked &&
        variant.inventory > @settings.inventory_threshold &&
        variant.adjusted? && variant.original_price.present? &&
        variant.last_written_price == variant.price &&
        variant.price > variant.original_price
    end
  end
end
