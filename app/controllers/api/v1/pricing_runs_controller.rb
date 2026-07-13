module Api
  module V1
    class PricingRunsController < BaseController
      def index
        runs = PricingRun.recent.limit(20)
        render json: { pricing_runs: runs.map { |r| PricingRunSerializer.new(r).as_json } }
      end

      def show
        run = PricingRun.find(params[:id])
        render json: PricingRunSerializer.new(run, include_changes: true).as_json
      end

      # "Run now" — enqueues a manual run. 409 if one is already in progress.
      def create
        run = PricingRun.start!(trigger: "manual")
        PricingRunJob.perform_later(run.id)
        render json: {
          enqueued: true,
          pricing_run: PricingRunSerializer.new(run).as_json
        }, status: :accepted
      rescue StandardError => e
        run&.fail!("enqueue failed: #{e.class}: #{e.message}")
        raise
      end
    end
  end
end
