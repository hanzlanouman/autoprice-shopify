require "rails_helper"

RSpec.describe "Api::V1::Products", type: :request do
  describe "GET /api/v1/products" do
    it "returns cached products with variant snapshots" do
      product = create(:product, title: "Zeta", price: "12.00", inventory_quantity: 3)
      run = PricingRun.create!(status: "completed", trigger: "manual")
      PriceChange.create!(
        pricing_run: run,
        product: product,
        shopify_variant_gid: product.variant_snapshots.first[:gid],
        status: "applied",
        action: "increase",
        source: "ai",
        old_price: 10,
        new_price: 12,
        raw_recommended_price: 12,
        inventory_level: 3,
        ai_reason: "Low stock",
        created_at: Time.current
      )

      get "/api/v1/products"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["products"].first["title"]).to eq("Zeta")
      variant = body["products"].first["variants"].first
      expect(variant["price"]).to eq("12.00")
      expect(variant).to have_key("eligible")
      expect(variant["latest_recommended_price"]).to eq("12.00")
      expect(variant["latest_old_price"]).to eq("10.00")
      expect(variant["latest_new_price"]).to eq("12.00")
      expect(variant["latest_reason"]).to eq("Low stock")
      expect(variant["previous_price"]).to eq("10.00")
      expect(variant["base_price"]).to eq("12.00")
      expect(variant["maximum_price"]).to eq("18.00")
      expect(body).to have_key("next_cursor")
      expect(body["synced_at"]).to be_present
    end


    it "does not present an old automated price as previous after an external edit" do
      product = create(:product, price: "15.00")
      run = PricingRun.create!(status: "completed", trigger: "manual")
      PriceChange.create!(
        pricing_run: run, product: product,
        shopify_variant_gid: product.variant_snapshots.first[:gid],
        status: "applied", action: "increase", source: "ai",
        old_price: 10, new_price: 12, inventory_level: 3
      )

      get "/api/v1/products"

      expect(response.parsed_body.dig("products", 0, "variants", 0, "previous_price")).to be_nil
    end

    it "cursor-paginates active products and omits stale cache rows" do
      first = create(:product, title: "First")
      second = create(:product, title: "Second")
      create(:product, title: "Removed", stale_at: Time.current)

      get "/api/v1/products", params: { limit: 1 }

      expect(response.parsed_body["products"].map { |p| p["id"] }).to eq([ first.id ])
      cursor = response.parsed_body["next_cursor"]

      get "/api/v1/products", params: { limit: 1, after_id: cursor }
      expect(response.parsed_body["products"].map { |p| p["id"] }).to eq([ second.id ])
    end
  end

  describe "POST /api/v1/products/sync" do
    it "uses the local catalogue when Shopify is not configured" do
      product = create(:product)

      post "/api/v1/products/sync"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["synced"]).to eq(1)
      expect(product.reload.stale_at).to be_nil
    end
  end
end
