module Api
  module V1
    # Base for all JSON API endpoints. Owns the single error envelope and the
    # exception → HTTP status taxonomy. Controllers stay thin and
    # never build error JSON by hand.
    class BaseController < ApplicationController
      # State-changing browser requests must carry the same-origin token from
      # the SPA shell. Keeping Rails' exception strategy prevents authenticated
      # browsers from being used as cross-site price-changing proxies.
      protect_from_forgery with: :exception

      rescue_from ActiveRecord::RecordNotFound do |e|
        render_error(:not_found, e.message, status: :not_found)
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render_error(
          :validation_failed,
          "Validation failed",
          status: :unprocessable_content,
          details: e.record.errors.messages
        )
      end

      rescue_from Pricing::RunInProgressError do |e|
        render_error(:run_in_progress, e.message, status: :conflict)
      end

      rescue_from ActionController::InvalidAuthenticityToken do
        render_error(:invalid_csrf_token, "The request authenticity token is missing or invalid", status: :forbidden)
      end

      rescue_from ActionController::ParameterMissing, ActionDispatch::Http::Parameters::ParseError do |e|
        render_error(:bad_request, e.message, status: :bad_request)
      end

      rescue_from Shopify::Error do |e|
        render_error(:shopify_unavailable, e.message, status: :service_unavailable)
      end

      rescue_from Shopify::Unauthorized do |e|
        render_error(:shopify_unauthorized, e.message, status: :unauthorized)
      end

      rescue_from Shopify::RateLimited do |e|
        render_error(:shopify_rate_limited, e.message, status: :too_many_requests)
      end

      # ActiveJob defines this exception lazily with its enqueuing module. A
      # string keeps fresh web processes from constantizing it before that
      # module has loaded; by the time the exception can be raised it exists.
      rescue_from "ActiveJob::EnqueueError" do |e|
        render_error(:job_enqueue_failed, e.message, status: :service_unavailable)
      end

      private

      # { "error": { "code":, "message":, "details"? } } — the only error shape.
      def render_error(code, message, status:, details: nil)
        payload = { code: code, message: message }
        payload[:details] = details if details.present?
        render json: { error: payload }, status: status
      end
    end
  end
end
