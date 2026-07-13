FactoryBot.define do
  factory :product do
    sequence(:shopify_gid) { |n| "gid://shopify/Product/#{1000 + n}" }
    title { "Sample Product" }
    product_type { "Widget" }
    vendor { "Acme" }
    status { "active" }
    gift_card { false }
    synced_at { Time.current }

    transient do
      variant_count { 1 }
      price { "50.00" }
      inventory_quantity { 5 }
      tracked { true }
    end

    variants do
      Array.new(variant_count) do |i|
        {
          gid: "#{shopify_gid.sub('Product', 'ProductVariant')}-#{i}",
          title: i.zero? ? "Default" : "Variant #{i}",
          price: price,
          inventory_quantity: inventory_quantity,
          tracked: tracked,
          original_price: nil,
          last_written_price: nil,
          last_adjusted_at: nil,
          inventory_at_last_adjustment: nil
        }
      end
    end
  end
end
