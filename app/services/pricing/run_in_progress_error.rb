module Pricing
  # Raised when a pricing run is requested while one is already running
  # (surfaces as HTTP 409 via Api::V1::BaseController).
  class RunInProgressError < StandardError; end
end
