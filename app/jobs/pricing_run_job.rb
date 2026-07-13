# Runs one full pricing pipeline. A Postgres advisory lock guarantees no two
# runs execute concurrently (A9); if the lock is held, this job exits cleanly.
# The run is always finalized (completed/failed) so none is ever stuck running.
class PricingRunJob < ApplicationJob
  queue_as :default

  def perform(run_id = nil, trigger: "manual")
    Pricing::ExecutionLock.with_lock do
      run = run_id ? PricingRun.find(run_id) : PricingRun.start!(trigger: trigger)
      next unless run.status == "running"

      if run.trigger == "scheduled" && !Setting.instance.auto_pricing_enabled?
        run.complete!({ cancelled: true, reason: "auto_pricing_disabled" })
        next
      end

      begin
        Pricing::RunOrchestrator.new.call(run)
      rescue StandardError => e
        run.fail!("#{e.class}: #{e.message}")
        Rails.logger.error("[pricing_run] run=#{run.id} failed: #{e.class}: #{e.message}")
      ensure
        run.fail!("run did not finish") if run.reload.status == "running"
      end
    end
  rescue Pricing::RunInProgressError => e
    Rails.logger.info("[pricing_run] skipped — #{e.message}")
    PricingRun.find_by(id: run_id)&.fail!(e.message)
  end
end
