module Pricing
  # Namespace + factory for recommenders. Chooses Gemini when configured,
  # otherwise the deterministic recommender so the pipeline always runs
  # (docs/ARCHITECTURE.md).
  module Recommender
    def self.for_environment
      if ::Gemini::Client.configured?
        Gemini.new
      elsif Shopify::Client.configured?
        Unavailable.new
      else
        Deterministic.new(source: "fallback")
      end
    end
  end
end
