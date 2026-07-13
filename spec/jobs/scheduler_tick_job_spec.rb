require "rails_helper"

RSpec.describe SchedulerTickJob, type: :job do
  def enqueued_pricing_runs
    # inline adapter runs jobs immediately; assert via created runs instead.
    PricingRun.where(trigger: "scheduled")
  end

  it "does nothing when auto pricing is disabled" do
    Setting.instance.update!(auto_pricing_enabled: false)
    expect { described_class.perform_now }.not_to change(PricingRun, :count)
  end

  it "does nothing when the schedule is not yet due" do
    Setting.instance.update!(auto_pricing_enabled: true, review_frequency: "daily")
    expect { described_class.perform_now }.not_to change(PricingRun, :count)
  end

  it "enqueues a scheduled run and advances next_run_at when due" do
    setting = Setting.instance
    setting.update!(auto_pricing_enabled: true, review_frequency: "hourly")
    setting.update_column(:next_run_at, 1.minute.ago)

    described_class.perform_now

    expect(enqueued_pricing_runs.count).to eq(1)
    expect(setting.reload.next_run_at).to be > Time.current
  end

  it "does not stack runs when one is already running" do
    setting = Setting.instance
    setting.update!(auto_pricing_enabled: true, review_frequency: "hourly")
    setting.update_column(:next_run_at, 1.minute.ago)
    PricingRun.create!(status: "running", trigger: "manual", started_at: Time.current)

    expect { described_class.perform_now }.not_to change { PricingRun.where(trigger: "scheduled").count }
  end

  it "finalizes stale running runs" do
    stale = PricingRun.create!(status: "running", trigger: "scheduled", started_at: 3.hours.ago)
    stale.update_column(:updated_at, 3.hours.ago)
    described_class.perform_now
    expect(stale.reload.status).to eq("failed")
  end
end
