# Single source of the settings JSON shape (docs/ARCHITECTURE.md). Money as a string.
class SettingSerializer
  def initialize(setting, currency: "USD")
    @setting = setting
    @currency = currency
  end

  def as_json(*)
    {
      inventory_threshold: @setting.inventory_threshold,
      max_price_percentage: Money.format(@setting.max_price_percentage),
      review_frequency: @setting.review_frequency,
      ai_behavior_prompt: @setting.ai_behavior_prompt,
      auto_pricing_enabled: @setting.auto_pricing_enabled,
      fallback_pricing_enabled: @setting.fallback_pricing_enabled,
      price_restoration_enabled: @setting.price_restoration_enabled,
      next_run_at: @setting.next_run_at&.iso8601,
      currency: @currency,
      ai_configured: Gemini::Client.configured?
    }
  end
end
