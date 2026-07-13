require "faraday"
require "faraday/retry"

module Shopify
  # The only HTTP-aware code for Shopify. Exposes intent-revealing methods over
  # the GraphQL Admin API and maps every failure into the Shopify::Error
  # taxonomy so nothing Faraday-specific escapes (docs/ARCHITECTURE.md).
  class Client
    DEFAULT_API_VERSION = "2026-07"
    THROTTLE_MAX_RETRIES = 5
    THROTTLE_WAIT_CAP = 8.0
    TOKEN_EXPIRY_SKEW = 60
    MAX_GRAPHQL_INPUT_SIZE = 250

    def self.configured?
      domain = ENV["SHOPIFY_STORE_DOMAIN"].present?
      static_token = ENV["SHOPIFY_ACCESS_TOKEN"].present?
      client_credentials = ENV["SHOPIFY_API_KEY"].present? && ENV["SHOPIFY_API_SECRET"].present?
      domain && (static_token || client_credentials)
    end

    # Real client when credentials exist, otherwise a local simulation so the
    # pricing pipeline runs on seed data without Shopify (docs/DEPLOYMENT.md).
    def self.build
      configured? ? new : LocalClient.new
    end

    def initialize(
      domain: ENV["SHOPIFY_STORE_DOMAIN"],
      token: ENV["SHOPIFY_ACCESS_TOKEN"],
      client_id: ENV["SHOPIFY_API_KEY"],
      client_secret: ENV["SHOPIFY_API_SECRET"],
      api_version: ENV.fetch("SHOPIFY_API_VERSION", DEFAULT_API_VERSION),
      clock: -> { Time.current }
    )
      @domain = normalize_domain(domain)
      @static_token = token.presence
      @client_id = client_id.presence
      @client_secret = client_secret.presence
      @api_version = api_version
      @clock = clock
      @token_mutex = Mutex.new
      unless @domain.present? && (@static_token || client_credentials?)
        raise NotConfigured, "Shopify domain and authentication credentials are not set"
      end
    end

    # Fetches every active product with its variants, following cursor
    # pagination. Returns an Array of raw product node Hashes.
    def fetch_products
      nodes = []
      cursor = nil
      loop do
        data = execute(Queries::PRODUCTS, cursor: cursor)
        page = connection_page!(data["products"], name: "products")
        page_nodes = page["nodes"]
        page_nodes.each { |node| fetch_remaining_variants(node) }
        nodes.concat(page_nodes)
        page_info = page["pageInfo"]
        break unless page_info["hasNextPage"]

        cursor = next_cursor!(page_info, connection_name: "products")
      end
      nodes
    end

    # Returns current live prices immediately before a write. Shopify limits
    # input arrays to 250 values, so larger products are read in safe chunks.
    def fetch_variant_prices(variant_gids)
      Array(variant_gids).compact.uniq.each_slice(MAX_GRAPHQL_INPUT_SIZE).flat_map do |ids|
        nodes = execute(Queries::VARIANT_PRICES, ids: ids)["nodes"]
        unless nodes.is_a?(Array)
          raise Unavailable, "Malformed Shopify response: invalid variant price nodes"
        end

        nodes.compact
      end
    end

    # variants: [{ id: gid, price: "12.34" }, ...] for a single product.
    # Returns the updated variant nodes; raises UserError on non-empty userErrors.
    def update_variant_prices(product_gid, variants)
      data = execute(
        Queries::VARIANTS_BULK_UPDATE,
        productId: product_gid,
        variants: variants.map { |v| { id: v[:id], price: v[:price].to_s } }
      )
      result = data["productVariantsBulkUpdate"]
      unless result.is_a?(Hash) && result["userErrors"].is_a?(Array)
        raise Unavailable, "Malformed Shopify variant update response"
      end

      errors = result["userErrors"]
      if errors.any?
        raise UserError.new(
          errors.map { |e| e["message"] }.join("; "),
          user_errors: errors
        )
      end
      result["productVariants"] || []
    end

    def fetch_shop_currency
      execute(Queries::SHOP).dig("shop", "currencyCode")
    end

    # A deliberately named low-level escape hatch for trusted maintenance
    # scripts (for example the live demo-store seeder). Application pricing
    # code should continue to use the intent-revealing methods above.
    def admin_graphql(document, **variables)
      execute(document, **variables)
    end

    private

    def normalize_domain(domain)
      return if domain.blank?

      normalized = domain.strip.sub(%r{\Ahttps?://}i, "").sub(%r{/+\z}, "").downcase
      unless normalized.match?(%r{\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.myshopify\.com\z})
        raise NotConfigured,
              "SHOPIFY_STORE_DOMAIN must be a myshopify.com hostname (for example, example-store.myshopify.com)"
      end

      normalized
    end

    def fetch_remaining_variants(product_node)
      unless product_node.is_a?(Hash) && product_node["id"].present?
        raise Unavailable, "Malformed Shopify response: product node is missing an id"
      end

      variants = connection_page!(product_node["variants"], name: "variants for #{product_node['id']}")
      page_info = variants["pageInfo"]

      while page_info["hasNextPage"]
        cursor = next_cursor!(page_info, connection_name: "variants for #{product_node['id']}")
        data = execute(Queries::PRODUCT_VARIANTS, productId: product_node["id"], cursor: cursor)
        product = data["product"]
        unless product
          raise Error, "Shopify product disappeared while variants were being paginated (#{product_node['id']})"
        end

        page = connection_page!(product["variants"], name: "variants for #{product_node['id']}")
        variants["nodes"].concat(page["nodes"])
        page_info = page["pageInfo"]
      end

      variants["pageInfo"] = page_info
    end

    def connection_page!(connection, name:)
      valid = connection.is_a?(Hash) &&
        connection["nodes"].is_a?(Array) &&
        connection["pageInfo"].is_a?(Hash) &&
        [ true, false ].include?(connection.dig("pageInfo", "hasNextPage"))
      return connection if valid

      raise Unavailable, "Malformed Shopify response: invalid #{name} connection"
    end

    def next_cursor!(page_info, connection_name:)
      cursor = page_info["endCursor"].presence
      return cursor if cursor

      raise Error, "Shopify returned hasNextPage without an endCursor for #{connection_name}"
    end

    # Runs a GraphQL operation, handling cost throttling with backoff and
    # mapping transport/GraphQL errors into the Shopify taxonomy.
    def execute(query, **variables)
      attempts = 0
      auth_refreshed = false
      loop do
        begin
          wait_for_cost_budget
          request_token = access_token
          response = connection.post do |req|
            req.headers["X-Shopify-Access-Token"] = request_token
            req.body = { query: query, variables: variables }.to_json
          end
          if response.status == 401 && @static_token.nil? && client_credentials? && !auth_refreshed
            auth_refreshed = true
            invalidate_access_token!(request_token)
            next
          end
          return handle_response(response)
        rescue RateLimited => e
          attempts += 1
          raise if attempts > THROTTLE_MAX_RETRIES

          sleep(e.retry_after || throttle_wait(attempts))
        rescue Faraday::Error => e
          raise Unavailable, "Shopify request failed: #{e.message}"
        end
      end
    end

    def handle_response(response)
      case response.status
      when 200
        parse_body(response.body)
      when 401, 403
        raise Unauthorized, "Shopify rejected the Admin token (#{response.status})"
      when 429
        raise RateLimited.new(
          "Shopify rate limited the request (429)",
          retry_after: retry_after_header(response)
        )
      when 500..599
        raise Unavailable, "Shopify returned #{response.status}"
      else
        raise Error, "Unexpected Shopify response (#{response.status})"
      end
    end

    def parse_body(body)
      payload = body.is_a?(Hash) ? body : JSON.parse(body.to_s)
      raise Unavailable, "Malformed Shopify response: expected a JSON object" unless payload.is_a?(Hash)

      if (errors = payload["errors"]).present?
        unless errors.is_a?(Array) && errors.all? { |error| error.is_a?(Hash) }
          raise Unavailable, "Malformed Shopify response: invalid errors"
        end

        if errors.any? { |error| error.dig("extensions", "code") == "THROTTLED" }
          raise RateLimited.new("Shopify GraphQL cost limit reached", retry_after: cost_wait(payload))
        end

        messages = errors.filter_map { |error| error["message"].presence }
        message = messages.join("; ").presence || "Shopify returned an unspecified GraphQL error"
        raise Error, message
      end

      data = payload["data"]
      raise Unavailable, "Malformed Shopify response: missing data" unless data.is_a?(Hash)

      record_cost_budget(payload)
      data
    rescue JSON::ParserError => e
      raise Unavailable, "Malformed Shopify response: #{e.message}"
    end

    def record_cost_budget(payload)
      @next_request_wait = cost_wait(payload)
    end

    # Shopify returns the query cost and the leaky-bucket state in
    # extensions.cost. Waiting before the next call avoids knowingly sending a
    # request whose estimated cost exceeds the currently available budget.
    def cost_wait(payload)
      cost = payload.dig("extensions", "cost")
      return unless cost.is_a?(Hash)

      requested = numeric(cost["requestedQueryCost"])
      throttle = cost["throttleStatus"]
      return unless requested && throttle.is_a?(Hash)

      available = numeric(throttle["currentlyAvailable"])
      restore_rate = numeric(throttle["restoreRate"])
      return unless available && restore_rate&.positive? && available < requested

      [ (requested - available) / restore_rate, THROTTLE_WAIT_CAP ].min
    end

    def wait_for_cost_budget
      wait = @next_request_wait
      @next_request_wait = nil
      sleep(wait) if wait&.positive?
    end

    def numeric(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def retry_after_header(response)
      value = numeric(response.headers["Retry-After"])
      value&.positive? ? [ value, THROTTLE_WAIT_CAP ].min : nil
    end

    def access_token
      return @static_token if @static_token

      @token_mutex.synchronize do
        return @access_token if cached_access_token_valid?

        fetch_access_token!
      end
    end

    def cached_access_token_valid?
      @access_token.present? && @token_expires_at &&
        @clock.call < (@token_expires_at - TOKEN_EXPIRY_SKEW)
    end

    def fetch_access_token!
      response = auth_connection.post("/admin/oauth/access_token") do |req|
        req.body = {
          grant_type: "client_credentials",
          client_id: @client_id,
          client_secret: @client_secret
        }
      end
      handle_token_response(response)
    rescue Faraday::Error => e
      raise Unavailable, "Shopify authentication request failed: #{e.message}"
    end

    def handle_token_response(response)
      case response.status
      when 200
        cache_token_response(response.body)
      when 400, 401, 403
        raise Unauthorized, "Shopify rejected the configured client credentials"
      when 429
        raise RateLimited.new(
          "Shopify rate limited the authentication request (429)",
          retry_after: retry_after_header(response)
        )
      when 500..599
        raise Unavailable, "Shopify authentication service returned #{response.status}"
      else
        raise Error, "Unexpected Shopify authentication response (#{response.status})"
      end
    end

    def cache_token_response(body)
      payload = body.is_a?(Hash) ? body : JSON.parse(body.to_s)
      token = payload["access_token"] if payload.is_a?(Hash)
      expires_in = numeric(payload["expires_in"]) if payload.is_a?(Hash)
      unless token.present? && expires_in&.positive?
        raise Unavailable, "Malformed Shopify authentication response"
      end

      @access_token = token
      @token_expires_at = @clock.call + expires_in
      @access_token
    rescue JSON::ParserError
      raise Unavailable, "Malformed Shopify authentication response"
    end

    def invalidate_access_token!(rejected_token)
      @token_mutex.synchronize do
        return unless @access_token == rejected_token

        @access_token = nil
        @token_expires_at = nil
      end
    end

    def client_credentials?
      @client_id.present? && @client_secret.present?
    end

    def throttle_wait(attempt)
      [ 2.0**(attempt - 1) * 0.5, THROTTLE_WAIT_CAP ].min
    end

    def connection
      @connection ||= Faraday.new(url: graphql_url) do |f|
        f.request :retry,
                  max: 2,
                  interval: 0.3,
                  backoff_factor: 2,
                  retry_statuses: [ 429, 500, 502, 503, 504 ],
                  exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]
        f.headers["Content-Type"] = "application/json"
        f.options.timeout = 30
        f.options.open_timeout = 5
        f.adapter Faraday.default_adapter
      end
    end

    def auth_connection
      @auth_connection ||= Faraday.new(url: "https://#{@domain}") do |f|
        f.request :url_encoded
        f.request :retry,
                  max: 2,
                  interval: 0.3,
                  backoff_factor: 2,
                  retry_statuses: [ 429, 500, 502, 503, 504 ],
                  exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]
        f.headers["Content-Type"] = "application/x-www-form-urlencoded"
        f.options.timeout = 30
        f.options.open_timeout = 5
        f.adapter Faraday.default_adapter
      end
    end

    def graphql_url
      "https://#{@domain}/admin/api/#{@api_version}/graphql.json"
    end
  end
end
