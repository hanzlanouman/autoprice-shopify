class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # The dashboard can trigger live price changes, so gate the whole app behind
  # HTTP basic auth whenever APP_PASSWORD is configured (see docs/DEPLOYMENT.md).
  # Left blank in local dev, the gate is disabled for convenience.
  before_action :authenticate_app!

  private

  def authenticate_app!
    password = ENV["APP_PASSWORD"].presence
    return if password.nil?

    username = ENV.fetch("APP_USERNAME", "admin")
    authenticate_or_request_with_http_basic("Dynamic Pricing Assistant") do |user, pass|
      ActiveSupport::SecurityUtils.secure_compare(user, username) &
        ActiveSupport::SecurityUtils.secure_compare(pass, password)
    end
  end
end
