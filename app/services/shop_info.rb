# Shop-level metadata. Currency is fetched once from Shopify and cached; without
# credentials it defaults to USD so the app runs on seed data (docs/DEPLOYMENT.md).
module ShopInfo
  module_function

  def currency
    Rails.cache.fetch("shop_currency", expires_in: 1.day) do
      next "USD" unless Shopify::Client.configured?

      begin
        Shopify::Client.new.fetch_shop_currency.presence || "USD"
      rescue Shopify::Error
        "USD"
      end
    end
  end
end
