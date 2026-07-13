module Shopify
  # Raised when SHOPIFY_STORE_DOMAIN / SHOPIFY_ACCESS_TOKEN are missing. Lets the
  # app boot and run on seed data without live credentials (docs/DEPLOYMENT.md).
  class NotConfigured < Error; end
end
