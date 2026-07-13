require "rails_helper"

RSpec.describe "App smoke", type: :request do
  it "serves the health check" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end

  it "serves the SPA shell at the root with the Vite entrypoint" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="root"')
    # Vite injects a hashed script tag for the built entrypoint.
    expect(response.body).to match(%r{<script[^>]+src="/vite[^"]+application[^"]+\.js"})
  end

  it "serves the SPA shell for unknown client-side routes" do
    get "/settings"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="root"')
  end
end
