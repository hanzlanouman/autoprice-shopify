require "rails_helper"

RSpec.describe Pricing::Recommender::Deterministic do
  subject(:recommender) { described_class.new }

  let(:settings) do
    Setting.new(inventory_threshold: 10, max_price_percentage: BigDecimal("150.00"))
  end

  def recommendation(price:, inventory:, original_price: nil)
    variant = Value::VariantSnapshot.new(
      gid: "variant-1", title: "Default", price: BigDecimal(price),
      inventory_quantity: inventory, tracked: true, gift_card: false,
      original_price: original_price && BigDecimal(original_price),
      last_written_price: nil, last_adjusted_at: nil,
      inventory_at_last_adjustment: nil
    )
    bounds = Pricing::Bounds.new(variant: variant, settings: settings)
    item = Struct.new(:variant, :bounds).new(variant, bounds)

    recommender.recommend([ item ], settings).first
  end

  it "applies a small non-zero signal exactly at the threshold" do
    expect(recommendation(price: "100.00", inventory: 10).price).to eq(BigDecimal("104.55"))
  end

  it "scales predictably with scarcity" do
    expect(recommendation(price: "100.00", inventory: 5).price).to eq(BigDecimal("127.27"))
  end

  it "anchors to base so a prior increase does not compound the target" do
    recommendation = recommendation(price: "120.00", inventory: 5, original_price: "100.00")
    expect(recommendation.price).to eq(BigDecimal("127.27"))
  end

  it "never proposes below the current price" do
    recommendation = recommendation(price: "140.00", inventory: 5, original_price: "100.00")
    expect(recommendation.price).to eq(BigDecimal("140.00"))
  end

  it "scales the cap for higher-priced products" do
    expect(recommendation(price: "800.00", inventory: 5).price).to eq(BigDecimal("1018.18"))
  end

  it "records the factors used in a merchant-readable reason" do
    reason = recommendation(price: "100.00", inventory: 5).reason
    expect(reason).to include("Inventory 5 of threshold 10", "base 100.00", "150.00% base-price ceiling")
  end
end
