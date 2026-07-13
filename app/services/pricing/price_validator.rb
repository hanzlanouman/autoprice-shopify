module Pricing
  # Stage 4: re-checks a recommendation against the SAME bounds the prompt was
  # built from (D2). This is where correctness lives — the AI is never trusted.
  # Rule 1 (<= ceiling), Rule 2 (>= floor), Rule 4 (malformed → rejected safely).
  # A recommendation equal to the floor is a valid "no change" and is skipped.
  class PriceValidator
    Outcome = Data.define(:status, :new_price, :rejection_reason)

    def initialize(bounds)
      @bounds = bounds
    end

    # Errors that mean "no AI opinion" (outage) are skipped so the next run can
    # catch up; a bad opinion (malformed) is rejected under Rule 4.
    SKIP_ERRORS = %i[gemini_unavailable no_recommendation].freeze

    def call(recommendation)
      unless recommendation.usable?
        reason = (recommendation.error || :malformed_response).to_s
        return SKIP_ERRORS.include?(recommendation.error) ? skip(reason) : reject(reason)
      end

      raw_price = Money.parse(recommendation.price)
      return reject("malformed_response") if raw_price.nil?
      return reject("below_current") if raw_price < @bounds.floor
      return reject("exceeds_max") if raw_price > @bounds.ceiling

      price = Money.round(raw_price)
      return reject("invalid_precision") if price != raw_price
      return skip("no_change_recommended") if price == @bounds.floor

      Outcome.new(status: :pending, new_price: price, rejection_reason: nil)
    end

    private

    def reject(reason)
      Outcome.new(status: "rejected", new_price: nil, rejection_reason: reason)
    end

    def skip(reason)
      Outcome.new(status: "skipped", new_price: nil, rejection_reason: reason)
    end
  end
end
