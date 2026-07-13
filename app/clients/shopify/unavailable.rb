module Shopify
  # Raised on 5xx / network / timeout failures talking to Shopify.
  class Unavailable < Error; end
end
