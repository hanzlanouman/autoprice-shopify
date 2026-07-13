module Shopify
  # Raised when a GraphQL mutation returns non-empty userErrors. Carries the
  # structured error list for the audit trail (docs/ARCHITECTURE.md).
  class UserError < Error
    attr_reader :user_errors

    def initialize(message, user_errors: [])
      super(message)
      @user_errors = user_errors
    end
  end
end
