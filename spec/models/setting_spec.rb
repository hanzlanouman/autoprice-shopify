require "rails_helper"

RSpec.describe Setting, type: :model do
  describe "validations" do
    it "requires a non-negative integer threshold" do
      expect(Setting.new(inventory_threshold: -1, max_price_percentage: 150)).not_to be_valid
    end

    it "requires a bounded maximum base-price percentage" do
      expect(Setting.new(inventory_threshold: 10, max_price_percentage: 99)).not_to be_valid
      expect(Setting.new(inventory_threshold: 10, max_price_percentage: 1001)).not_to be_valid
    end

    it "rejects unknown frequencies" do
      expect(Setting.new(inventory_threshold: 10, max_price_percentage: 150, review_frequency: "yearly")).not_to be_valid
    end

    it "caps the AI prompt length" do
      expect(Setting.new(inventory_threshold: 10, max_price_percentage: 150, ai_behavior_prompt: "x" * 501)).not_to be_valid
    end
  end

  describe ".instance" do
    it "returns a singleton, creating it once" do
      first = described_class.instance
      expect(described_class.instance.id).to eq(first.id)
      expect(described_class.count).to eq(1)
    end
  end

  describe "next_run_at recomputation" do
    it "is set when auto pricing is enabled" do
      setting = described_class.instance
      setting.update!(auto_pricing_enabled: true, review_frequency: "daily")
      expect(setting.next_run_at).to be_within(1.minute).of(1.day.from_now)
    end

    it "is cleared when auto pricing is disabled" do
      setting = described_class.instance
      setting.update!(auto_pricing_enabled: true)
      setting.update!(auto_pricing_enabled: false)
      expect(setting.next_run_at).to be_nil
    end

    it "recomputes when the frequency changes while enabled" do
      setting = described_class.instance
      setting.update!(auto_pricing_enabled: true, review_frequency: "daily")
      setting.update!(review_frequency: "hourly")
      expect(setting.next_run_at).to be_within(1.minute).of(1.hour.from_now)
    end
  end

  describe "#due? and #advance_next_run!" do
    it "is due when enabled and next_run_at has passed" do
      setting = described_class.instance
      setting.update!(auto_pricing_enabled: true)
      setting.update_column(:next_run_at, 1.minute.ago)
      expect(setting.due?).to be(true)
    end

    it "advances the schedule from the given time" do
      setting = described_class.instance
      setting.update!(review_frequency: "hourly")
      setting.advance_next_run!(from: Time.utc(2026, 1, 1, 12, 0, 0))
      expect(setting.next_run_at).to eq(Time.utc(2026, 1, 1, 13, 0, 0))
    end

    it "supports a one-minute demo cadence" do
      setting = described_class.instance
      setting.update!(auto_pricing_enabled: true, review_frequency: "minute")
      expect(setting.next_run_at).to be_within(5.seconds).of(1.minute.from_now)
    end
  end
end
