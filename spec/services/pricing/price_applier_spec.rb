require "rails_helper"

RSpec.describe Pricing::PriceApplier do
  let(:product) { create(:product, price: "100.00", inventory_quantity: 4) }
  let(:variant_gid) { product.variant_snapshots.first[:gid] }
  let(:run) { PricingRun.create!(status: "running", trigger: "manual", started_at: Time.current) }
  let(:change) do
    Value::PlannedChange.new(
      product_gid: product.shopify_gid,
      product_id: product.id,
      variant_gid: variant_gid,
      variant_title: "Default",
      status: :pending,
      action: "increase",
      source: "ai",
      old_price: BigDecimal("100.00"),
      new_price: BigDecimal("120.00"),
      raw_recommended_price: BigDecimal("120.00"),
      inventory_level: 4,
      ai_reason: "Low inventory",
      rejection_reason: nil
    )
  end

  it "durably records an intent before confirming cache and history" do
    client = instance_double(Shopify::Client)
    allow(client).to receive(:fetch_variant_prices)
      .and_return([ { "id" => variant_gid, "price" => "100.00" } ])
    allow(client).to receive(:update_variant_prices)
      .and_return([ { "id" => variant_gid, "price" => "120.00" } ])

    result = described_class.new(client: client).call(run, [ change ]).first

    expect(result.status).to eq("applied")
    expect(PriceWriteIntent.find_by!(shopify_variant_gid: variant_gid).status).to eq("applied")
    expect(run.price_changes.find_by!(shopify_variant_gid: variant_gid).new_price).to eq(BigDecimal("120.00"))
    expect(product.reload.variant_snapshots.first[:last_written_price]).to eq("120.00")
  end

  it "leaves an uncertain transport outcome for live-price reconciliation" do
    client = instance_double(Shopify::Client)
    allow(client).to receive(:fetch_variant_prices)
      .and_return([ { "id" => variant_gid, "price" => "100.00" } ])
    allow(client).to receive(:update_variant_prices).and_raise(Shopify::Unavailable, "timeout")

    result = described_class.new(client: client).call(run, [ change ]).first

    expect(result.status).to eq("reconciling")
    expect(PriceWriteIntent.find_by!(shopify_variant_gid: variant_gid).status).to eq("pending")
    expect(run.price_changes).to be_empty

    Pricing::WriteIntentReconciler.new.call([ live_product_node(price: "120.00") ])

    expect(PriceWriteIntent.find_by!(shopify_variant_gid: variant_gid).status).to eq("applied")
    expect(run.price_changes.find_by!(shopify_variant_gid: variant_gid).status).to eq("applied")
    expect(product.reload.variant_snapshots.first[:last_written_price]).to eq("120.00")
  end

  it "records a failed write when live Shopify still has the expected old price" do
    PriceWriteIntent.create!(
      pricing_run: run,
      product: product,
      product_gid: product.shopify_gid,
      shopify_variant_gid: variant_gid,
      variant_title: "Default",
      action: "increase",
      source: "ai",
      expected_old_price: 100,
      target_price: 120,
      inventory_level: 4,
      reason: "Low inventory"
    )

    Pricing::WriteIntentReconciler.new.call([ live_product_node(price: "100.00") ])

    expect(PriceWriteIntent.find_by!(shopify_variant_gid: variant_gid).status).to eq("failed")
    expect(run.price_changes.find_by!(shopify_variant_gid: variant_gid).status).to eq("failed")
  end

  def live_product_node(price:)
    {
      "id" => product.shopify_gid,
      "variants" => {
        "nodes" => [ { "id" => variant_gid, "price" => price } ]
      }
    }
  end
end
