module Pricing
  # THE single place pricing bounds and increase-eligibility are computed
  # (docs/ARCHITECTURE.md). The prompt builder serializes bounds INTO the Gemini
  # request and the validator checks responses AGAINST them, so what we ask for
  # and what we enforce can never drift.
  class Bounds
    # Ordered reasons a variant is NOT eligible for an increase.
    def initialize(variant:, settings:)
      @variant = variant
      @settings = settings
    end

    # Lowest allowed recommendation: never below the current price (Rule 2).
    def floor
      @variant.price
    end

    # Merchant-controlled baseline. Before the first adjustment this is the
    # current Shopify price; later runs retain the price from before the first
    # automated increase. A merchant edit safely rebases it in ProductFetcher.
    def base
      @variant.original_price || @variant.price
    end

    # A setting of 150 means each variant is capped at 150% of its own base:
    # 100 -> 150, 800 -> 1200. This remains deterministic regardless of LLM use.
    def ceiling
      multiplier = BigDecimal(@settings.max_price_percentage.to_s) / 100
      Money.round(base * multiplier)
    end

    def eligible?
      reason == :eligible
    end

    # :eligible or the machine-readable reason it was skipped.
    def reason
      return :gift_card if @variant.gift_card
      return :untracked unless @variant.tracked
      return :out_of_stock if @variant.inventory <= 0
      return :above_threshold if @variant.inventory > @settings.inventory_threshold
      return :at_ceiling if floor >= ceiling
      return :already_adjusted if guard_blocks?

      :eligible
    end

    private

    # Re-adjustment guard (A3): once adjusted, skip until inventory drops further.
    def guard_blocks?
      @variant.adjusted? &&
        @variant.inventory_at_last_adjustment.present? &&
        @variant.inventory >= @variant.inventory_at_last_adjustment
    end
  end
end
