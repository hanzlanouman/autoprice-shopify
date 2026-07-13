module Pricing
  module Recommender
    # Safe production behavior when Shopify is configured but Gemini is not:
    # emit an unavailable result so the merchant's explicit fallback setting,
    # rather than missing infrastructure, decides whether formula pricing runs.
    class Unavailable < Base
      def source_label = "ai"

      def recommend(eligible, _settings)
        eligible.map do |item|
          Value::Recommendation.failed(
            variant_gid: item.variant.gid,
            error: :gemini_unavailable,
            source: "ai"
          )
        end
      end
    end
  end
end
