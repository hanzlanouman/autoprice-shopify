# This application can autonomously modify live store prices. A production
# process must therefore fail closed instead of silently exposing the control
# plane when an authentication variable was forgotten.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  password = ENV["APP_PASSWORD"].to_s
  if password.length < 16
    raise "APP_PASSWORD must be set to at least 16 characters in production"
  end
end
