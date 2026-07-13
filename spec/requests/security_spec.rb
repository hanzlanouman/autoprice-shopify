require "rails_helper"

RSpec.describe "Application security", type: :request do
  around do |example|
    old_user = ENV["APP_USERNAME"]
    old_password = ENV["APP_PASSWORD"]
    example.run
  ensure
    ENV["APP_USERNAME"] = old_user
    ENV["APP_PASSWORD"] = old_password
  end

  it "requires HTTP Basic credentials when the control-plane password is configured" do
    ENV["APP_USERNAME"] = "merchant"
    ENV["APP_PASSWORD"] = "a-secure-test-password"

    get "/api/v1/settings"
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/settings", headers: {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "merchant", "a-secure-test-password"
      )
    }
    expect(response).to have_http_status(:ok)
  end

  it "rejects state-changing API requests without a valid CSRF token" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    post "/api/v1/pricing_runs"

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
