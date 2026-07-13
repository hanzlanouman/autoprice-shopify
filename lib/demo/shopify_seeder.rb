module Demo
  # Creates demo products on a live Shopify dev store (bin/rails demo:seed_shopify).
  # Requires SHOPIFY_* credentials and is exercised only against a real store, so
  # it is intentionally kept out of the autoloaded app tree.
  class ShopifySeeder
    LOCATION_QUERY = <<~GRAPHQL.freeze
      query { locations(first: 1) { nodes { id } } }
    GRAPHQL

    PRODUCT_SET = <<~GRAPHQL.freeze
      mutation ProductSet($input: ProductSetInput!) {
        productSet(synchronous: true, input: $input) {
          product { id title }
          userErrors { field message }
        }
      }
    GRAPHQL

    def initialize(catalogue:, client: Shopify::Client.new)
      @catalogue = catalogue
      @client = client
    end

    def call
      location_id = fetch_location_id
      @catalogue.each do |title, type, vendor, gift_card, variants|
        create_product(title, type, vendor, gift_card, variants, location_id)
      end
      puts "Created #{@catalogue.size} products on #{ENV['SHOPIFY_STORE_DOMAIN']}."
    end

    private

    def fetch_location_id
      data = @client.admin_graphql(LOCATION_QUERY)
      data.dig("locations", "nodes", 0, "id") or abort("No Shopify location found.")
    end

    def create_product(title, type, vendor, gift_card, variants, location_id)
      input = {
        title: title,
        productType: type,
        vendor: vendor,
        giftCard: gift_card,
        status: "ACTIVE",
        productOptions: [ { name: "Title", values: variants.map { |v| { name: v[0].presence || "Default" } } } ],
        variants: variants.map { |suffix, price, qty, tracked|
          variant_input(suffix, price, qty, tracked, location_id)
        }
      }
      result = @client.admin_graphql(PRODUCT_SET, input: input)
      errors = result.dig("productSet", "userErrors") || []
      warn "  ! #{title}: #{errors.map { |e| e['message'] }.join('; ')}" if errors.any?
      puts "  + #{title}" if errors.empty?
    end

    def variant_input(suffix, price, qty, tracked, location_id)
      base = {
        optionValues: [ { optionName: "Title", name: suffix.presence || "Default" } ],
        price: price,
        inventoryItem: { tracked: tracked }
      }
      base[:inventoryQuantities] = [ { locationId: location_id, name: "available", quantity: qty } ] if tracked && !qty.nil?
      base
    end
  end
end
