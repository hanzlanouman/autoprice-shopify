require "rails_helper"

RSpec.describe "Api::V1::Settings", type: :request do
  describe "GET /api/v1/settings" do
    it "returns the settings with money as a string" do
      get "/api/v1/settings"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["max_price_percentage"]).to eq("150.00")
      expect(body).to have_key("ai_configured")
      expect(body).to have_key("currency")
      expect(body["price_restoration_enabled"]).to be(false)
    end
  end

  describe "PATCH /api/v1/settings" do
    it "updates and returns the new values" do
      patch "/api/v1/settings", params: { settings: { inventory_threshold: 30, price_restoration_enabled: true } }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["inventory_threshold"]).to eq(30)
      expect(response.parsed_body["price_restoration_enabled"]).to be(true)
    end

    it "returns 422 with field-level details on invalid input" do
      patch "/api/v1/settings", params: { settings: { max_price_percentage: 99 } }
      expect(response).to have_http_status(:unprocessable_content)
      body = response.parsed_body
      expect(body.dig("error", "code")).to eq("validation_failed")
      expect(body.dig("error", "details")).to have_key("max_price_percentage")
    end
  end
end
