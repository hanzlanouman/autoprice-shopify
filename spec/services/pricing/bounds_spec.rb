require "rails_helper"

RSpec.describe Pricing::Bounds do
  def settings(threshold: 10, max_percentage: "150.00")
    Setting.new(inventory_threshold: threshold, max_price_percentage: BigDecimal(max_percentage))
  end

  def variant(price: "100.00", inventory: 5, tracked: true, gift_card: false,
              original_price: nil, last_adjusted_at: nil, inventory_at_last_adjustment: nil)
    Value::VariantSnapshot.new(
      gid: "gid://shopify/ProductVariant/1",
      title: "Default",
      price: BigDecimal(price),
      inventory_quantity: inventory,
      tracked: tracked,
      gift_card: gift_card,
      original_price: original_price && BigDecimal(original_price),
      last_written_price: nil,
      last_adjusted_at: last_adjusted_at,
      inventory_at_last_adjustment: inventory_at_last_adjustment
    )
  end

  describe "floor and ceiling" do
    it "uses current as floor and computes the ceiling from base price" do
      bounds = described_class.new(variant: variant(price: "100.00"), settings: settings(max_percentage: "150.00"))
      expect(bounds.floor).to eq(BigDecimal("100.00"))
      expect(bounds.base).to eq(BigDecimal("100.00"))
      expect(bounds.ceiling).to eq(BigDecimal("150.00"))
    end


    it "scales the same percentage across high-priced products" do
      bounds = described_class.new(variant: variant(price: "800.00"), settings: settings(max_percentage: "150.00"))
      expect(bounds.ceiling).to eq(BigDecimal("1200.00"))
    end

    it "retains the original base after an automated increase" do
      bounds = described_class.new(
        variant: variant(price: "130.00", original_price: "100.00"),
        settings: settings(max_percentage: "150.00")
      )
      expect(bounds.base).to eq(BigDecimal("100.00"))
      expect(bounds.ceiling).to eq(BigDecimal("150.00"))
    end
  end

  describe "eligibility matrix" do
    it "is eligible when tracked, in stock, at/below threshold, below ceiling" do
      expect(described_class.new(variant: variant(inventory: 5), settings: settings).eligible?).to be(true)
    end

    it "is eligible exactly at the threshold (<=)" do
      b = described_class.new(variant: variant(inventory: 10), settings: settings(threshold: 10))
      expect(b.reason).to eq(:eligible)
    end

    it "is above_threshold one over the threshold" do
      b = described_class.new(variant: variant(inventory: 11), settings: settings(threshold: 10))
      expect(b.reason).to eq(:above_threshold)
    end

    it "is out_of_stock at zero inventory (A10)" do
      expect(described_class.new(variant: variant(inventory: 0), settings: settings).reason).to eq(:out_of_stock)
    end

    it "treats negative (oversold) inventory as out_of_stock (A6)" do
      expect(described_class.new(variant: variant(inventory: -3), settings: settings).reason).to eq(:out_of_stock)
    end

    it "is untracked when inventory is not tracked (A6)" do
      expect(described_class.new(variant: variant(tracked: false, inventory: nil), settings: settings).reason).to eq(:untracked)
    end

    it "is gift_card for gift card products (A11)" do
      expect(described_class.new(variant: variant(gift_card: true), settings: settings).reason).to eq(:gift_card)
    end

    it "is at_ceiling when price already meets the max" do
      b = described_class.new(variant: variant(price: "150.00", original_price: "100.00"), settings: settings)
      expect(b.reason).to eq(:at_ceiling)
    end

    it "is at_ceiling when price exceeds the max" do
      b = described_class.new(variant: variant(price: "160.00", original_price: "100.00"), settings: settings)
      expect(b.reason).to eq(:at_ceiling)
    end
  end

  describe "re-adjustment guard (A3)" do
    it "blocks when already adjusted and inventory has not dropped further" do
      v = variant(inventory: 5, last_adjusted_at: 1.day.ago, inventory_at_last_adjustment: 5)
      expect(described_class.new(variant: v, settings: settings).reason).to eq(:already_adjusted)
    end

    it "allows again when inventory dropped further since the last adjustment" do
      v = variant(inventory: 3, last_adjusted_at: 1.day.ago, inventory_at_last_adjustment: 5)
      expect(described_class.new(variant: v, settings: settings).reason).to eq(:eligible)
    end
  end
end
