require "rails_helper"

RSpec.describe Pricing::ProductFetcher do
  let(:client) { instance_double(Shopify::Client) }
  let(:reconciler) { double("write intent reconciler", call: nil) }
  subject(:fetcher) { described_class.new(client: client, reconciler: reconciler) }

  def node(gid:, variants:, gift_card: false)
    {
      "id" => gid,
      "title" => "Product #{gid}",
      "productType" => "Type",
      "vendor" => "Vendor",
      "status" => "ACTIVE",
      "isGiftCard" => gift_card,
      "variants" => { "nodes" => variants }
    }
  end

  def variant(gid:, price:, qty:, tracked: true)
    {
      "id" => gid,
      "title" => "Default",
      "price" => price,
      "inventoryQuantity" => qty,
      "inventoryItem" => { "tracked" => tracked }
    }
  end

  it "maps nodes to snapshots and upserts the cache" do
    allow(client).to receive(:fetch_products).and_return([
      node(gid: "gid://shopify/Product/1",
           variants: [ variant(gid: "gid://shopify/ProductVariant/11", price: "10.00", qty: 3) ])
    ])

    snapshots = fetcher.call

    expect(snapshots.size).to eq(1)
    variant_snapshot = snapshots.first.variants.first
    expect(variant_snapshot.price).to eq(BigDecimal("10.00"))
    expect(variant_snapshot.inventory_quantity).to eq(3)

    product = Product.find_by(shopify_gid: "gid://shopify/Product/1")
    expect(product.variant_snapshots.first[:price]).to eq("10.00")
    expect(product.synced_at).to be_present
    expect(reconciler).to have_received(:call)
  end

  it "preserves guard state across syncs when the price is unchanged" do
    product = create(:product, shopify_gid: "gid://shopify/Product/2")
    gid = product.variant_snapshots.first[:gid]
    product.update!(variants: [ product.variant_snapshots.first.merge(
      price: "50.00", last_written_price: "50.00", original_price: "40.00",
      last_adjusted_at: 1.day.ago.iso8601, inventory_at_last_adjustment: 5
    ) ])

    allow(client).to receive(:fetch_products).and_return([
      node(gid: "gid://shopify/Product/2",
           variants: [ variant(gid: gid, price: "50.00", qty: 4) ])
    ])

    snapshot = fetcher.call.first.variants.first
    expect(snapshot.original_price).to eq(BigDecimal("40.00"))
    expect(snapshot.last_adjusted_at).to be_present
  end

  it "re-bases when the merchant changed the price (A12)" do
    product = create(:product, shopify_gid: "gid://shopify/Product/3")
    gid = product.variant_snapshots.first[:gid]
    product.update!(variants: [ product.variant_snapshots.first.merge(
      price: "50.00", last_written_price: "50.00", original_price: "40.00",
      last_adjusted_at: 1.day.ago.iso8601, inventory_at_last_adjustment: 5
    ) ])

    # Shopify now reports a different price than we last wrote.
    allow(client).to receive(:fetch_products).and_return([
      node(gid: "gid://shopify/Product/3",
           variants: [ variant(gid: gid, price: "44.00", qty: 4) ])
    ])

    snapshot = fetcher.call.first.variants.first
    expect(snapshot.original_price).to eq(BigDecimal("44.00"))
    expect(snapshot.last_written_price).to be_nil
    expect(snapshot.last_adjusted_at).to be_nil
  end

  it "soft-marks products missing from a complete sync as stale" do
    missing = create(:product, shopify_gid: "gid://shopify/Product/missing")
    current_gid = "gid://shopify/Product/current"
    allow(client).to receive(:fetch_products).and_return([
      node(gid: current_gid,
           variants: [ variant(gid: "gid://shopify/ProductVariant/current", price: "10.00", qty: 3) ])
    ])

    fetcher.call

    expect(missing.reload.stale_at).to be_present
    expect(Product.find_by!(shopify_gid: current_gid).stale_at).to be_nil
    expect(Product.active).not_to include(missing)
  end

  it "clears stale state when a product reappears" do
    product = create(
      :product,
      shopify_gid: "gid://shopify/Product/returned",
      stale_at: 1.day.ago
    )
    allow(client).to receive(:fetch_products).and_return([
      node(gid: product.shopify_gid,
           variants: [ variant(gid: "gid://shopify/ProductVariant/returned", price: "10.00", qty: 3) ])
    ])

    fetcher.call

    expect(product.reload.stale_at).to be_nil
    expect(Product.active).to include(product)
  end

  it "does not mark cached products stale when Shopify fetch fails" do
    product = create(:product)
    allow(client).to receive(:fetch_products).and_raise(Shopify::Unavailable, "network down")

    expect { fetcher.call }.to raise_error(Shopify::Unavailable)
    expect(product.reload.stale_at).to be_nil
    expect(reconciler).not_to have_received(:call)
  end
end
