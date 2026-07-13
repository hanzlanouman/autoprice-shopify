require "rails_helper"

RSpec.describe "Api::V1::PriceChanges", type: :request do
  let(:run) { PricingRun.create!(status: "completed", trigger: "manual") }

  def change!(status:, gid: "v#{rand(10_000)}", product: nil)
    PriceChange.create!(pricing_run: run, product: product, shopify_variant_gid: gid, status: status,
                        action: "increase", source: "ai", old_price: 10, new_price: 12,
                        inventory_level: 3, created_at: Time.current)
  end

  it "paginates with a cursor" do
    5.times { change!(status: "applied") }

    get "/api/v1/price_changes", params: { limit: 2 }
    body = response.parsed_body
    expect(body["items"].size).to eq(2)
    expect(body["next_cursor"]).to be_present

    get "/api/v1/price_changes", params: { limit: 2, before_id: body["next_cursor"] }
    expect(response.parsed_body["items"].size).to eq(2)
  end

  it "filters by status" do
    change!(status: "applied")
    change!(status: "rejected")

    get "/api/v1/price_changes", params: { status: "rejected" }
    items = response.parsed_body["items"]
    expect(items.size).to eq(1)
    expect(items.first["status"]).to eq("rejected")
  end

  it "filters history by product" do
    selected = create(:product, title: "Selected")
    other = create(:product, title: "Other")
    change!(status: "applied", product: selected)
    change!(status: "applied", product: other)

    get "/api/v1/price_changes", params: { product_id: selected.id }

    items = response.parsed_body["items"]
    expect(items.size).to eq(1)
    expect(items.first["product_title"]).to eq("Selected")
  end

  it "searches product and variant names case-insensitively" do
    selected = create(:product, title: "Steel Bottle", vendor: "Northstar")
    other = create(:product, title: "Ceramic Mug")
    change!(status: "applied", gid: "steel-large", product: selected).update_column(:variant_title, "Large")
    change!(status: "applied", gid: "mug-default", product: other)

    get "/api/v1/price_changes", params: { query: "STEEL" }
    expect(response.parsed_body["items"].map { |item| item["product_title"] }).to eq([ "Steel Bottle" ])

    get "/api/v1/price_changes", params: { query: "large" }
    expect(response.parsed_body["items"].map { |item| item["shopify_variant_gid"] }).to eq([ "steel-large" ])
  end

  it "sorts oldest first while preserving cursor pagination" do
    first = change!(status: "applied", gid: "first")
    second = change!(status: "applied", gid: "second")
    third = change!(status: "applied", gid: "third")

    get "/api/v1/price_changes", params: { sort: "oldest", limit: 2 }
    body = response.parsed_body
    expect(body["items"].map { |item| item["id"] }).to eq([ first.id, second.id ])

    get "/api/v1/price_changes", params: { sort: "oldest", limit: 2, before_id: body["next_cursor"] }
    expect(response.parsed_body["items"].map { |item| item["id"] }).to eq([ third.id ])
  end

  it "filters by exact variant" do
    change!(status: "applied", gid: "selected")
    change!(status: "applied", gid: "other")

    get "/api/v1/price_changes", params: { variant_gid: "selected" }

    expect(response.parsed_body["items"].map { |item| item["shopify_variant_gid"] }).to eq([ "selected" ])
  end
end
