module Shopify
  # Raised on 401/403 from Shopify (bad or under-scoped Admin token).
  class Unauthorized < Error; end
end
