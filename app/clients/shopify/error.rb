module Shopify
  # Base for every error the Shopify adapter raises. The client maps raw
  # Faraday/HTTP failures into this small taxonomy so nothing HTTP-specific
  # escapes the adapter boundary (docs/ARCHITECTURE.md). Subclasses live alongside.
  class Error < StandardError; end
end
