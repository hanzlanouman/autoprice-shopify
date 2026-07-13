require "rails_helper"

RSpec.describe Pricing::PriceValidator do
  # floor 100, ceiling 150
  let(:bounds) do
    variant = Value::VariantSnapshot.new(
      gid: "v1", title: "V", price: BigDecimal("100.00"), inventory_quantity: 5,
      tracked: true, gift_card: false, original_price: nil, last_written_price: nil,
      last_adjusted_at: nil, inventory_at_last_adjustment: nil
    )
    Pricing::Bounds.new(
      variant: variant,
      settings: Setting.new(inventory_threshold: 10, max_price_percentage: BigDecimal("150.00"))
    )
  end

  def rec(price)
    Value::Recommendation.valid(variant_gid: "v1", price: price, reason: "r", source: "ai")
  end

  it "accepts a price inside the range (pending apply)" do
    outcome = described_class.new(bounds).call(rec(BigDecimal("130.00")))
    expect(outcome.status).to eq(:pending)
    expect(outcome.new_price).to eq(BigDecimal("130.00"))
  end

  it "accepts exactly the ceiling" do
    expect(described_class.new(bounds).call(rec(BigDecimal("150.00"))).status).to eq(:pending)
  end

  it "rejects above the ceiling (Rule 1)" do
    outcome = described_class.new(bounds).call(rec(BigDecimal("150.01")))
    expect(outcome.status).to eq("rejected")
    expect(outcome.rejection_reason).to eq("exceeds_max")
  end

  it "does not round an out-of-bounds value down into the valid range" do
    outcome = described_class.new(bounds).call(rec(BigDecimal("150.004")))
    expect(outcome.status).to eq("rejected")
    expect(outcome.rejection_reason).to eq("exceeds_max")
  end

  it "rejects excessive currency precision" do
    outcome = described_class.new(bounds).call(rec(BigDecimal("120.001")))
    expect(outcome.status).to eq("rejected")
    expect(outcome.rejection_reason).to eq("invalid_precision")
  end

  it "rejects below the current price (Rule 2)" do
    outcome = described_class.new(bounds).call(rec(BigDecimal("99.99")))
    expect(outcome.status).to eq("rejected")
    expect(outcome.rejection_reason).to eq("below_current")
  end

  it "skips a no-change recommendation equal to the floor" do
    outcome = described_class.new(bounds).call(rec(BigDecimal("100.00")))
    expect(outcome.status).to eq("skipped")
    expect(outcome.rejection_reason).to eq("no_change_recommended")
  end

  it "rejects a malformed recommendation safely (Rule 4)" do
    bad = Value::Recommendation.failed(variant_gid: "v1", error: :malformed_response, source: "ai")
    outcome = described_class.new(bounds).call(bad)
    expect(outcome.status).to eq("rejected")
    expect(outcome.rejection_reason).to eq("malformed_response")
  end

  it "rejects non-finite numeric output safely" do
    outcome = described_class.new(bounds).call(rec(BigDecimal("NaN")))
    expect(outcome.status).to eq("rejected")
    expect(outcome.rejection_reason).to eq("malformed_response")
  end
end
