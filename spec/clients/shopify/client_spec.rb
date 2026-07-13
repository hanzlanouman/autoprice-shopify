require "rails_helper"

RSpec.describe Shopify::Client do
  let(:domain) { "test-shop.myshopify.com" }
  let(:token) { "shpat_test" }
  let(:url) { "https://#{domain}/admin/api/2026-07/graphql.json" }
  let(:token_url) { "https://#{domain}/admin/oauth/access_token" }

  subject(:client) { described_class.new(domain: domain, token: token, api_version: "2026-07") }

  def stub_graphql(body:, status: 200)
    stub_request(:post, url).to_return(
      status: status,
      headers: { "Content-Type" => "application/json" },
      body: body.to_json
    )
  end

  def stub_token_exchange(token: "dynamic-token", expires_in: 86_399, status: 200)
    stub_request(:post, token_url).to_return(
      status: status,
      headers: { "Content-Type" => "application/json" },
      body: status == 200 ? { access_token: token, expires_in: expires_in }.to_json : "{}"
    )
  end

  describe ".configured?" do
    it "is false without credentials" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SHOPIFY_STORE_DOMAIN").and_return(nil)
      expect(described_class.configured?).to be(false)
    end

    it "accepts client credentials when a static Admin token is absent" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SHOPIFY_STORE_DOMAIN").and_return(domain)
      allow(ENV).to receive(:[]).with("SHOPIFY_ACCESS_TOKEN").and_return(nil)
      allow(ENV).to receive(:[]).with("SHOPIFY_API_KEY").and_return("client-id")
      allow(ENV).to receive(:[]).with("SHOPIFY_API_SECRET").and_return("client-secret")

      expect(described_class.configured?).to be(true)
    end
  end

  describe "#initialize" do
    it "defaults new integrations to the current stable API line" do
      expect(described_class::DEFAULT_API_VERSION).to eq("2026-07")
    end

    it "raises NotConfigured when credentials are missing" do
      expect { described_class.new(domain: nil, token: nil) }
        .to raise_error(Shopify::NotConfigured)
    end

    it "normalizes a copied Shopify URL" do
      copied_url_client = described_class.new(
        domain: " https://TEST-SHOP.myshopify.com/ ",
        token: token,
        api_version: "2026-07"
      )
      stub_graphql(body: { data: { shop: { currencyCode: "USD" } } })

      expect(copied_url_client.fetch_shop_currency).to eq("USD")
    end

    it "rejects a non-Shopify hostname with a useful message" do
      expect { described_class.new(domain: "https://example.com", token: token) }
        .to raise_error(Shopify::NotConfigured, /myshopify\.com hostname/)
    end
  end

  describe "#fetch_products" do
    it "follows cursor pagination and concatenates nodes" do
      page1 = {
        data: { products: {
          pageInfo: { hasNextPage: true, endCursor: "CUR1" },
          nodes: [ {
            id: "gid://shopify/Product/1",
            title: "A",
            variants: { pageInfo: { hasNextPage: false, endCursor: nil }, nodes: [] }
          } ]
        } }
      }
      page2 = {
        data: { products: {
          pageInfo: { hasNextPage: false, endCursor: nil },
          nodes: [ {
            id: "gid://shopify/Product/2",
            title: "B",
            variants: { pageInfo: { hasNextPage: false, endCursor: nil }, nodes: [] }
          } ]
        } }
      }
      stub_request(:post, url)
        .to_return({ status: 200, headers: { "Content-Type" => "application/json" }, body: page1.to_json },
                   { status: 200, headers: { "Content-Type" => "application/json" }, body: page2.to_json })

      nodes = client.fetch_products
      expect(nodes.map { |n| n["title"] }).to eq(%w[A B])
    end

    it "paginates products with more than 100 variants" do
      first_variants = Array.new(10) do |index|
        { id: "gid://shopify/ProductVariant/#{index + 1}", title: "V#{index + 1}" }
      end
      product_page = {
        data: { products: {
          pageInfo: { hasNextPage: false, endCursor: nil },
          nodes: [ {
            id: "gid://shopify/Product/1",
            title: "Large product",
            variants: {
              pageInfo: { hasNextPage: true, endCursor: "VARIANT_CURSOR_10" },
              nodes: first_variants
            }
          } ]
        } }
      }
      variant_page = {
        data: { product: { variants: {
          pageInfo: { hasNextPage: false, endCursor: nil },
          nodes: Array.new(92) do |index|
            number = index + 11
            { id: "gid://shopify/ProductVariant/#{number}", title: "V#{number}" }
          end
        } } }
      }
      stub_request(:post, url)
        .to_return({ status: 200, headers: { "Content-Type" => "application/json" }, body: product_page.to_json },
                   { status: 200, headers: { "Content-Type" => "application/json" }, body: variant_page.to_json })

      product = client.fetch_products.first

      expect(product.dig("variants", "nodes").size).to eq(102)
      variant_page_request = a_request(:post, url).with do |request|
        body = JSON.parse(request.body)
        body["query"].include?("query ProductVariants") &&
          body.dig("variables", "productId") == "gid://shopify/Product/1" &&
          body.dig("variables", "cursor") == "VARIANT_CURSOR_10"
      end
      expect(variant_page_request).to have_been_made.once
    end

    it "rejects a non-advancing product cursor instead of looping forever" do
      stub_graphql(body: { data: { products: {
        pageInfo: { hasNextPage: true, endCursor: nil },
        nodes: []
      } } })

      expect { client.fetch_products }.to raise_error(Shopify::Error, /without an endCursor/)
    end
  end

  describe "client-credentials authentication" do
    def credential_client(clock: -> { Time.current })
      described_class.new(
        domain: domain,
        token: nil,
        client_id: "client-id",
        client_secret: "client-secret",
        api_version: "2026-07",
        clock: clock
      )
    end

    it "exchanges form-encoded credentials and reuses the token until expiry" do
      stub_token_exchange
      stub_request(:post, url)
        .with(headers: { "X-Shopify-Access-Token" => "dynamic-token" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { data: { shop: { currencyCode: "USD" } } }.to_json
        )

      authenticated_client = credential_client
      2.times { expect(authenticated_client.fetch_shop_currency).to eq("USD") }

      expect(
        a_request(:post, token_url).with(body: {
          "grant_type" => "client_credentials",
          "client_id" => "client-id",
          "client_secret" => "client-secret"
        })
      ).to have_been_made.once
    end

    it "refreshes an expired cached token" do
      now = Time.utc(2026, 7, 12, 12)
      clock = -> { now }
      stub_request(:post, token_url)
        .to_return(
          { status: 200, body: { access_token: "token-1", expires_in: 3_600 }.to_json },
          { status: 200, body: { access_token: "token-2", expires_in: 3_600 }.to_json }
        )
      stub_request(:post, url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { data: { shop: { currencyCode: "USD" } } }.to_json
      )
      authenticated_client = credential_client(clock: clock)

      authenticated_client.fetch_shop_currency
      now += 3_601
      authenticated_client.fetch_shop_currency

      expect(a_request(:post, token_url)).to have_been_made.twice
      expect(a_request(:post, url).with(headers: { "X-Shopify-Access-Token" => "token-1" }))
        .to have_been_made.once
      expect(a_request(:post, url).with(headers: { "X-Shopify-Access-Token" => "token-2" }))
        .to have_been_made.once
    end

    it "invalidates and refreshes once when Shopify returns 401" do
      stub_request(:post, token_url)
        .to_return(
          { status: 200, body: { access_token: "token-1", expires_in: 3_600 }.to_json },
          { status: 200, body: { access_token: "token-2", expires_in: 3_600 }.to_json }
        )
      stub_request(:post, url)
        .to_return(
          { status: 401, body: "{}" },
          { status: 200, body: { data: { shop: { currencyCode: "USD" } } }.to_json }
        )

      expect(credential_client.fetch_shop_currency).to eq("USD")
      expect(a_request(:post, token_url)).to have_been_made.twice
      expect(a_request(:post, url)).to have_been_made.twice
    end

    it "does not loop when the refreshed token is also rejected" do
      stub_request(:post, token_url)
        .to_return(
          { status: 200, body: { access_token: "token-1", expires_in: 3_600 }.to_json },
          { status: 200, body: { access_token: "token-2", expires_in: 3_600 }.to_json }
        )
      stub_request(:post, url).to_return(status: 401, body: "{}")

      expect { credential_client.fetch_shop_currency }.to raise_error(Shopify::Unauthorized)
      expect(a_request(:post, token_url)).to have_been_made.twice
      expect(a_request(:post, url)).to have_been_made.twice
    end

    it "does not expose the client secret when the exchange is rejected" do
      stub_token_exchange(status: 401)

      expect { credential_client.fetch_shop_currency }
        .to raise_error(Shopify::Unauthorized) { |error| expect(error.message).not_to include("client-secret") }
    end
  end

  describe "static-token authentication" do
    it "sends the configured Admin token without an OAuth exchange" do
      stub_graphql(body: { data: { shop: { currencyCode: "USD" } } })

      expect(client.fetch_shop_currency).to eq("USD")
      expect(a_request(:post, url).with(headers: { "X-Shopify-Access-Token" => token }))
        .to have_been_made.once
      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end

  describe "#update_variant_prices" do
    it "raises UserError with details on non-empty userErrors" do
      stub_graphql(body: { data: { productVariantsBulkUpdate: {
        productVariants: [],
        userErrors: [ { field: [ "price" ], message: "Price is invalid" } ]
      } } })

      expect {
        client.update_variant_prices("gid://shopify/Product/1", [ { id: "v1", price: "10.00" } ])
      }.to raise_error(Shopify::UserError, /Price is invalid/)
    end

    it "returns updated variants on success" do
      stub_graphql(body: { data: { productVariantsBulkUpdate: {
        productVariants: [ { id: "v1", price: "10.00" } ],
        userErrors: []
      } } })

      result = client.update_variant_prices("gid://shopify/Product/1", [ { id: "v1", price: "10.00" } ])
      expect(result.first["price"]).to eq("10.00")
    end
  end

  describe "#fetch_variant_prices" do
    it "returns live variant nodes for the requested ids" do
      ids = [ "gid://shopify/ProductVariant/1", "gid://shopify/ProductVariant/2" ]
      stub_graphql(body: { data: { nodes: [
        { id: ids.first, price: "10.00" },
        { id: ids.second, price: "20.00" }
      ] } })

      result = client.fetch_variant_prices(ids)

      expect(result).to eq([
        { "id" => ids.first, "price" => "10.00" },
        { "id" => ids.second, "price" => "20.00" }
      ])
      request = a_request(:post, url).with do |graphql_request|
        body = JSON.parse(graphql_request.body)
        body["query"].include?("query VariantPrices") && body.dig("variables", "ids") == ids
      end
      expect(request).to have_been_made.once
    end

    it "does not make a request for an empty id list" do
      expect(client.fetch_variant_prices([])).to eq([])
      expect(a_request(:post, url)).not_to have_been_made
    end

    it "chunks id lists at Shopify's 250-input limit" do
      ids = Array.new(251) { |index| "gid://shopify/ProductVariant/#{index + 1}" }
      first_request = stub_request(:post, url)
        .with(body: {
          query: Shopify::Queries::VARIANT_PRICES,
          variables: { ids: ids.first(250) }
        })
        .to_return(status: 200, body: { data: { nodes: [] } }.to_json)
      second_request = stub_request(:post, url)
        .with(body: {
          query: Shopify::Queries::VARIANT_PRICES,
          variables: { ids: [ ids.last ] }
        })
        .to_return(status: 200, body: { data: { nodes: [] } }.to_json)

      expect(client.fetch_variant_prices(ids)).to eq([])
      expect(first_request).to have_been_requested.once
      expect(second_request).to have_been_requested.once
    end
  end

  describe "error mapping" do
    it "maps 401 to Unauthorized" do
      stub_graphql(body: {}, status: 401)
      expect { client.fetch_products }.to raise_error(Shopify::Unauthorized)
    end

    it "maps 500 to Unavailable" do
      stub_graphql(body: {}, status: 500)
      expect { client.fetch_products }.to raise_error(Shopify::Unavailable)
    end

    it "maps Faraday transport failures to Unavailable" do
      connection = instance_double(Faraday::Connection)
      allow(client).to receive(:connection).and_return(connection)
      allow(connection).to receive(:post).and_raise(Faraday::ConnectionFailed, "connection reset")

      expect { client.fetch_products }
        .to raise_error(Shopify::Unavailable, /connection reset/)
    end

    it "retries on THROTTLED then succeeds" do
      throttled = { errors: [ { message: "Throttled", extensions: { code: "THROTTLED" } } ] }
      ok = { data: { products: { pageInfo: { hasNextPage: false }, nodes: [] } } }
      stub_request(:post, url)
        .to_return({ status: 200, headers: { "Content-Type" => "application/json" }, body: throttled.to_json },
                   { status: 200, headers: { "Content-Type" => "application/json" }, body: ok.to_json })
      allow(client).to receive(:sleep)

      expect(client.fetch_products).to eq([])
    end

    it "uses GraphQL throttle metadata to wait before the next page" do
      page1 = {
        data: { products: { pageInfo: { hasNextPage: true, endCursor: "CUR1" }, nodes: [] } },
        extensions: { cost: {
          requestedQueryCost: 100,
          throttleStatus: { currentlyAvailable: 50, restoreRate: 25 }
        } }
      }
      page2 = { data: { products: { pageInfo: { hasNextPage: false }, nodes: [] } } }
      stub_request(:post, url)
        .to_return({ status: 200, headers: { "Content-Type" => "application/json" }, body: page1.to_json },
                   { status: 200, headers: { "Content-Type" => "application/json" }, body: page2.to_json })
      allow(client).to receive(:sleep)

      expect(client.fetch_products).to eq([])
      expect(client).to have_received(:sleep).with(2.0).once
    end
  end
end
