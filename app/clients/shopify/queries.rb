module Shopify
  # All GraphQL documents live here so query changes are deliberate and diffable
  # (docs/ARCHITECTURE.md). Prices live on variants; we fetch inventory + tracked so the
  # pipeline can decide eligibility. The 40 x 10 nested page stays comfortably
  # below Shopify's single-query cost ceiling; larger variant sets continue in
  # independent 250-node pages.
  module Queries
    PRODUCTS = <<~GRAPHQL.freeze
      query Products($cursor: String) {
        products(first: 40, after: $cursor, query: "status:active") {
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            title
            productType
            vendor
            status
            isGiftCard
            variants(first: 10) {
              pageInfo { hasNextPage endCursor }
              nodes {
                id
                title
                price
                inventoryQuantity
                inventoryItem { tracked }
              }
            }
          }
        }
      }
    GRAPHQL

    # Shopify variants are a connection independent of the products
    # connection. The first page is embedded above to keep the common case to
    # one request; larger variant sets continue here.
    PRODUCT_VARIANTS = <<~GRAPHQL.freeze
      query ProductVariants($productId: ID!, $cursor: String) {
        product(id: $productId) {
          variants(first: 250, after: $cursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              title
              price
              inventoryQuantity
              inventoryItem { tracked }
            }
          }
        }
      }
    GRAPHQL

    VARIANT_PRICES = <<~GRAPHQL.freeze
      query VariantPrices($ids: [ID!]!) {
        nodes(ids: $ids) {
          ... on ProductVariant {
            id
            price
          }
        }
      }
    GRAPHQL

    # Updates one or more variants' prices for a single product.
    VARIANTS_BULK_UPDATE = <<~GRAPHQL.freeze
      mutation UpdateVariantPrices($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
        productVariantsBulkUpdate(allowPartialUpdates: false, productId: $productId, variants: $variants) {
          productVariants {
            id
            price
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    SHOP = <<~GRAPHQL.freeze
      query Shop {
        shop {
          currencyCode
        }
      }
    GRAPHQL
  end
end
