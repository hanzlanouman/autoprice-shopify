# Demo data tasks for local and Shopify development-store evaluation.
#
#   bin/rails demo:seed_local    # populate the local product cache directly
#                                # (no Shopify credentials needed) — the path
#                                # used for local development and verification.
#   bin/rails demo:seed_shopify  # create the same catalogue on a live Shopify
#                                # dev store (requires SHOPIFY_* credentials).
#
# The catalogue deliberately spans the eligibility matrix: below/at/above
# threshold, sold out, untracked inventory, multi-variant, gift card, and a
# high-priced item near a typical ceiling.
namespace :demo do
  # Each entry: title, type, vendor, gift_card, [variants].
  # Variant: [suffix, price, inventory_quantity, tracked]
  CATALOGUE = [
    [ "Aged Reserve Whiskey", "Spirits", "Highland Co", false, [ [ "", "120.00", 4, true ] ] ],
    [ "Organic Cotton T-Shirt", "Apparel", "GreenThread", false,
     [ [ "S", "22.00", 150, true ], [ "M", "22.00", 7, true ], [ "L", "22.00", 2, true ] ] ],
    [ "Limited Edition Sneakers", "Footwear", "Sole Society", false, [ [ "", "95.00", 0, true ] ] ],
    [ "Handmade Wall Clock", "Home", "TimeCraft", false, [ [ "", "45.00", nil, false ] ] ],
    [ "Store Gift Card", "Gift Card", "House", true, [ [ "$50", "50.00", nil, false ] ] ],
    [ "Ceramic Coffee Mug", "Home", "PotteryLane", false, [ [ "", "15.00", 38, true ] ] ],
    [ "Brass Desk Lamp", "Lighting", "Lumière", false, [ [ "", "60.00", 9, true ] ] ],
    [ "Pocket Notebook", "Stationery", "PaperTrail", false, [ [ "", "8.00", 240, true ] ] ]
  ].freeze

  desc "Populate the local product cache with demo data (no Shopify needed)"
  task seed_local: :environment do
    now = Time.current
    rows = CATALOGUE.each_with_index.map do |(title, type, vendor, gift_card, variants), pi|
      product_id = 1001 + pi
      {
        shopify_gid: "gid://shopify/Product/#{product_id}",
        title: title,
        product_type: type,
        vendor: vendor,
        status: "active",
        gift_card: gift_card,
        synced_at: now,
        variants: variants.each_with_index.map do |(suffix, price, qty, tracked), vi|
          {
            gid: "gid://shopify/ProductVariant/#{product_id * 10 + vi}",
            title: suffix.presence || "Default",
            price: price,
            inventory_quantity: qty,
            tracked: tracked,
            original_price: nil,
            last_written_price: nil,
            last_adjusted_at: nil,
            inventory_at_last_adjustment: nil
          }
        end,
        created_at: now,
        updated_at: now
      }
    end

    Product.upsert_all(rows, unique_by: :shopify_gid)
    puts "Seeded #{rows.size} products (#{rows.sum { |r| r[:variants].size }} variants) into the local cache."
  end

  desc "Create demo products on the live Shopify dev store (requires credentials)"
  task seed_shopify: :environment do
    unless Shopify::Client.configured?
      abort "Shopify is not configured. Set SHOPIFY_STORE_DOMAIN and either a static access token or client credentials."
    end
    require_relative "../demo/shopify_seeder"
    Demo::ShopifySeeder.new(catalogue: CATALOGUE).call
  end
end
