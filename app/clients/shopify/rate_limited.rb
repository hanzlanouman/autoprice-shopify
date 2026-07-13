module Shopify
  # Raised when the GraphQL cost throttle is exhausted and retries are spent.
  class RateLimited < Error
    attr_reader :retry_after

    def initialize(message, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end
end
