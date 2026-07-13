# Recurring tick (every minute via config/recurring.yml). Enqueues
# a scheduled pricing run when Setting#next_run_at is due, advancing the schedule
# from now so a downed worker doesn't cause a burst of catch-up runs (D3). Also
# self-heals runs left stuck "running" by a crashed worker (F15).
class SchedulerTickJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 2.hours

  def perform
    finalize_stale_runs

    setting = Setting.instance
    setting.with_lock do
      return unless setting.due?
      return if PricingRun.running? # never stack runs; the job's advisory lock also guards

      run = PricingRun.start!(trigger: "scheduled")
      PricingRunJob.perform_later(run.id)
      setting.advance_next_run!
    end
  rescue Pricing::RunInProgressError
    # The partial unique index is the final arbiter if two scheduler ticks race.
    nil
  rescue StandardError => e
    run&.fail!("enqueue failed: #{e.class}: #{e.message}")
    raise
  end

  private

  def finalize_stale_runs
    PricingRun.where(status: "running")
              .where(updated_at: ..STALE_AFTER.ago)
              .find_each { |run| run.fail!("run did not finish (stale)") }
  end
end
