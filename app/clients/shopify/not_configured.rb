module Shopify
  # Raised when SHOPIFY_STORE_DOMAIN / SHOPIFY_ACCESS_TOKEN are missing. Lets the
  # app boot and run on seed data without live credentials.
  class NotConfigured < Error; end
end
