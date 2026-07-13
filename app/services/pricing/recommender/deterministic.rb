module Pricing
  module Recommender
    # Base-anchored scarcity pricing within the exact bounds the validator
    # enforces:
    #   target = base + (ceiling - base) * scarcity
    #   scarcity = (threshold - inventory + 1) / (threshold + 1)
    #
    # The same inventory always produces the same target, so repeated runs do
    # not compound from a previously raised current price. The +1 produces a
    # small signal exactly at the threshold; sold-out items are excluded first.
    # Doubles as the dev/test recommender (no API key needed) and the opt-in
    # outage fallback. Rows it produces are labeled source "fallback" (docs/ARCHITECTURE.md).
    class Deterministic < Base
      def initialize(source: "fallback")
        @source = source
      end

      def source_label
        @source
      end

      def recommend(eligible, settings)
        eligible.map do |item|
          variant = item.variant
          bounds = item.bounds
          score = scarcity(variant, settings)
          target = interpolate(bounds.base, bounds.ceiling, score)
          price = [ bounds.floor, target ].max
          Value::Recommendation.valid(
            variant_gid: variant.gid,
            price: price,
            reason: reason_for(variant, settings, bounds, score, price),
            source: @source
          )
        end
      end

      private

      def scarcity(variant, settings)
        threshold = settings.inventory_threshold
        return BigDecimal(1) if threshold <= 0

        numerator = threshold - variant.inventory + 1
        (BigDecimal(numerator) / BigDecimal(threshold + 1)).clamp(BigDecimal(0), BigDecimal(1))
      end

      def interpolate(base, ceiling, scarcity)
        Money.round(base + (ceiling - base) * scarcity)
      end

      def reason_for(variant, settings, bounds, scarcity, price)
        scarcity_percent = (scarcity * 100).round
        "Inventory #{variant.inventory} of threshold #{settings.inventory_threshold} " \
          "produces a #{scarcity_percent}% scarcity score. From base #{Money.format(bounds.base)}, " \
          "the deterministic target is #{Money.format(price)} within the " \
          "#{Money.format(settings.max_price_percentage)}% base-price ceiling."
      end
    end
  end
end
