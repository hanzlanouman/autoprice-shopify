module Shopify
  # Drop-in stand-in for Shopify::Client used when no credentials are configured,
  # so the whole pipeline runs on local seed data for demos and reviews
  # (docs/DEPLOYMENT.md). It reads the product cache as if it were the store and lets
  # PriceApplier persist writes back to the cache. Same interface as Client, so
  # the pipeline code is identical either way (dependency injection).
  class LocalClient
    def fetch_products
      Product.active.order(:title).map do |product|
        {
          "id" => product.shopify_gid,
          "title" => product.title,
          "productType" => product.product_type,
          "vendor" => product.vendor,
          "status" => product.status.to_s.upcase,
          "isGiftCard" => product.gift_card,
          "variants" => {
            "nodes" => product.variant_snapshots.map do |v|
              {
                "id" => v[:gid],
                "title" => v[:title],
                "price" => v[:price],
                "inventoryQuantity" => v[:inventory_quantity],
                "inventoryItem" => { "tracked" => v[:tracked] }
              }
            end
          }
        }
      end
    end

    # No-op remote write: PriceApplier is the single cache writer and persists
    # the new prices, so simulation and the real path share one code path.
    def update_variant_prices(_product_gid, variants)
      variants.map { |v| { "id" => v[:id], "price" => v[:price].to_s } }
    end

    def fetch_variant_prices(variant_gids)
      wanted = Array(variant_gids).compact.uniq
      wanted_lookup = wanted.index_with(true)
      prices = Product.active.each_with_object({}) do |product, result|
        product.variant_snapshots.each do |variant|
          result[variant[:gid]] = variant[:price] if wanted_lookup.key?(variant[:gid])
        end
      end
      wanted.filter_map do |gid|
        { "id" => gid, "price" => prices[gid] } if prices.key?(gid)
      end
    end

    def fetch_shop_currency
      "USD"
    end
  end
end
