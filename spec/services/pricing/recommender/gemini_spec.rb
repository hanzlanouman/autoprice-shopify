require "rails_helper"

RSpec.describe Pricing::Recommender::Gemini do
  let(:gemini_client) { instance_double(Gemini::Client) }
  subject(:recommender) { described_class.new(client: gemini_client) }

  let(:settings) { Setting.new(inventory_threshold: 10, max_price_percentage: BigDecimal("150.00")) }

  def eligible_item(gid:, price: "100.00", inventory: 5)
    variant = Value::VariantSnapshot.new(
      gid: gid, title: "V", price: BigDecimal(price), inventory_quantity: inventory,
      tracked: true, gift_card: false, original_price: nil, last_written_price: nil,
      last_adjusted_at: nil, inventory_at_last_adjustment: nil
    )
    product = Value::ProductSnapshot.new(
      gid: "p", title: "P", product_type: "T", vendor: "Vend", status: "active",
      gift_card: false, variants: [ variant ]
    )
    Pricing::EligibilityFilter::Eligible.new(
      product: product, variant: variant,
      bounds: Pricing::Bounds.new(variant: variant, settings: settings)
    )
  end

  it "parses a valid response into a usable recommendation" do
    allow(gemini_client).to receive(:generate_json).and_return(
      [ { "variant_gid" => "v1", "recommended_price" => "130.00", "reason" => "Low stock" } ]
    )

    rec = recommender.recommend([ eligible_item(gid: "v1") ], settings).first
    expect(rec).to be_usable
    expect(rec.price).to eq(BigDecimal("130.00"))
    expect(rec.source).to eq("ai")
  end

  it "marks a variant missing from the response as malformed" do
    allow(gemini_client).to receive(:generate_json).and_return([])
    rec = recommender.recommend([ eligible_item(gid: "v1") ], settings).first
    expect(rec.usable?).to be(false)
    expect(rec.error).to eq(:malformed_response)
  end

  it "rejects a non-numeric or non-positive price as malformed" do
    allow(gemini_client).to receive(:generate_json).and_return(
      [ { "variant_gid" => "v1", "recommended_price" => "free", "reason" => "x" } ]
    )
    rec = recommender.recommend([ eligible_item(gid: "v1") ], settings).first
    expect(rec.error).to eq(:malformed_response)
  end

  it "ignores unknown variant_gids in the response" do
    allow(gemini_client).to receive(:generate_json).and_return(
      [ { "variant_gid" => "unknown", "recommended_price" => "130.00", "reason" => "x" } ]
    )
    rec = recommender.recommend([ eligible_item(gid: "v1") ], settings).first
    expect(rec.error).to eq(:malformed_response)
  end

  it "degrades a failed chunk to gemini_unavailable (skipped downstream)" do
    allow(gemini_client).to receive(:generate_json).and_raise(Gemini::Unavailable, "down")
    rec = recommender.recommend([ eligible_item(gid: "v1") ], settings).first
    expect(rec.error).to eq(:gemini_unavailable)
  end

  it "batches large eligible sets into multiple calls" do
    items = Array.new(45) { |i| eligible_item(gid: "v#{i}") }
    allow(gemini_client).to receive(:generate_json).and_return([])
    recommender.recommend(items, settings)
    expect(gemini_client).to have_received(:generate_json).exactly(3).times # 20 + 20 + 5
  end
end
