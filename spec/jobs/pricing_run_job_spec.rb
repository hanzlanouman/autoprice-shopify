require "rails_helper"

RSpec.describe PricingRunJob, type: :job do
  it "creates and completes a run" do
    create(:product, price: "100.00", inventory_quantity: 4)
    Setting.instance.update!(inventory_threshold: 10, max_price_percentage: BigDecimal("150.00"))

    described_class.perform_now(trigger: "manual")

    run = PricingRun.last
    expect(run.status).to eq("completed")
    expect(run.trigger).to eq("manual")
  end

  it "finalizes the run as failed when the pipeline raises" do
    allow_any_instance_of(Pricing::RunOrchestrator).to receive(:call).and_raise("boom")

    described_class.perform_now

    run = PricingRun.last
    expect(run.status).to eq("failed")
    expect(run.error_message).to include("boom")
  end

  it "does not leave a run stuck in running (advisory lock released)" do
    create(:product, price: "100.00", inventory_quantity: 4)
    described_class.perform_now
    expect(PricingRun.where(status: "running")).to be_empty
    # A subsequent run still acquires the lock and completes.
    described_class.perform_now
    expect(PricingRun.where(status: "running")).to be_empty
  end
end
