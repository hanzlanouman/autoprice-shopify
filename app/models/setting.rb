# Singleton holding the merchant's pricing rules. Access via
# Setting.instance. next_run_at is recomputed here whenever the cadence or the
# master switch changes, so scheduling logic lives in exactly one place.
class Setting < ApplicationRecord
  FREQUENCIES = {
    "minute" => 1.minute,
    "hourly" => 1.hour,
    "daily" => 1.day,
    "weekly" => 1.week,
    "monthly" => 1.month
  }.freeze

  AI_PROMPT_MAX = 500

  validates :inventory_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_price_percentage,
            numericality: { greater_than_or_equal_to: 100, less_than_or_equal_to: 1000 }
  validates :review_frequency, inclusion: { in: FREQUENCIES.keys }
  validates :ai_behavior_prompt, length: { maximum: AI_PROMPT_MAX }, allow_blank: true
  validates :singleton_key, inclusion: { in: [ 1 ] }, uniqueness: true

  before_save :reset_next_run,
              if: -> { will_save_change_to_review_frequency? || will_save_change_to_auto_pricing_enabled? }

  def self.instance
    find_or_create_by!(singleton_key: 1)
  rescue ActiveRecord::RecordNotUnique
    find_by!(singleton_key: 1)
  end

  def frequency_interval
    FREQUENCIES.fetch(review_frequency)
  end

  # Advance the schedule from `from`, used by the scheduler after a run (D3).
  def advance_next_run!(from: Time.current)
    update!(next_run_at: from + frequency_interval)
  end

  def due?(now: Time.current)
    auto_pricing_enabled && next_run_at.present? && next_run_at <= now
  end

  private

  def reset_next_run
    self.next_run_at = auto_pricing_enabled ? Time.current + frequency_interval : nil
  end
end
