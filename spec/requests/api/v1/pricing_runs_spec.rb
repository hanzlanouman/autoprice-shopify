require "rails_helper"

RSpec.describe "Api::V1::PricingRuns", type: :request do
  describe "POST /api/v1/pricing_runs" do
    it "enqueues a run (which completes inline in tests)" do
      create(:product, price: "100.00", inventory_quantity: 4)

      post "/api/v1/pricing_runs"

      expect(response).to have_http_status(:accepted)
      expect(PricingRun.last.status).to eq("completed")
      expect(response.parsed_body.dig("pricing_run", "id")).to eq(PricingRun.last.id)
    end

    it "returns 409 when a run is already in progress" do
      PricingRun.create!(status: "running", trigger: "manual", started_at: Time.current)

      post "/api/v1/pricing_runs"

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig("error", "code")).to eq("run_in_progress")
    end
  end

  describe "GET /api/v1/pricing_runs" do
    it "lists recent runs with stats" do
      PricingRun.create!(status: "completed", trigger: "scheduled", stats: { "applied" => 2 })
      get "/api/v1/pricing_runs"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pricing_runs"].first["stats"]).to eq("applied" => 2)
    end
  end

  describe "GET /api/v1/pricing_runs/:id" do
    it "returns a run with its price changes" do
      run = PricingRun.create!(status: "completed", trigger: "manual")
      PriceChange.create!(pricing_run: run, shopify_variant_gid: "v1", status: "applied",
                          action: "increase", source: "ai", old_price: 10, new_price: 12,
                          inventory_level: 3, created_at: Time.current)

      get "/api/v1/pricing_runs/#{run.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["price_changes"].size).to eq(1)
    end
  end
end
