module Pricing
  module Recommender
    # Interface every recommender implements. Gemini and the deterministic
    # fallback are interchangeable behind this, which is what lets the whole
    # pipeline run and be tested without the network.
    class Base
      # eligible: Array<EligibilityFilter::Eligible>, settings: Setting
      # Returns Array<Value::Recommendation> (one per eligible variant).
      def recommend(_eligible, _settings)
        raise NotImplementedError
      end

      # Row source stamped on recommendations ("ai"/"fallback"/"system") and
      # reported in run stats.
      def source_label
        "system"
      end
    end
  end
end
