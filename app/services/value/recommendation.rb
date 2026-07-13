module Value
  # A recommender's output for one variant. `price` is nil when the recommender
  # couldn't produce a usable value; `error` then holds a machine-readable reason
  # (e.g. :malformed_response, :gemini_unavailable). `source` is ai/fallback/system.
  Recommendation = Data.define(:variant_gid, :price, :reason, :source, :error) do
    def self.valid(variant_gid:, price:, reason:, source:)
      new(variant_gid: variant_gid, price: price, reason: reason, source: source, error: nil)
    end

    def self.failed(variant_gid:, error:, source:)
      new(variant_gid: variant_gid, price: nil, reason: nil, source: source, error: error)
    end

    def usable?
      error.nil? && !price.nil?
    end
  end
end
