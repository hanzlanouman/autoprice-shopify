require "rails_helper"

RSpec.describe Shopify::LocalClient do
  describe "#fetch_variant_prices" do
    it "returns prices from active, non-stale cached products" do
      active = create(:product, price: "12.34")
      stale = create(:product, price: "99.99", stale_at: 1.hour.ago)
      active_gid = active.variant_snapshots.first[:gid]
      stale_gid = stale.variant_snapshots.first[:gid]

      expect(described_class.new.fetch_variant_prices([ active_gid, stale_gid, "missing" ])).to eq([
        { "id" => active_gid, "price" => "12.34" }
      ])
    end
  end
end
