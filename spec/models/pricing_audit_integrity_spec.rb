require "rails_helper"

RSpec.describe "Pricing audit integrity", type: :model do
  def create_change(run)
    PriceChange.create!(
      pricing_run: run,
      shopify_variant_gid: "gid://shopify/ProductVariant/1",
      status: "applied",
      action: "increase",
      source: "fallback",
      old_price: 100,
      new_price: 110
    )
  end

  it "cannot update or destroy a recorded pricing decision" do
    run = PricingRun.create!(status: "completed", trigger: "manual")
    change = create_change(run)

    expect { change.update!(ai_reason: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { change.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "cannot destroy a run after a pricing decision has been recorded" do
    run = PricingRun.create!(status: "completed", trigger: "manual")
    create_change(run)

    expect { run.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
