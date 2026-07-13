# One execution of the pricing pipeline — the unit the dashboard reports on
# (docs/ARCHITECTURE.md). At most one run is "running" at a time (advisory lock + partial
# unique index).
class PricingRun < ApplicationRecord
  STATUSES = %w[running completed failed].freeze
  TRIGGERS = %w[scheduled manual].freeze

  # Runs form the root of the pricing audit trail. Refuse accidental cleanup
  # through Active Record when either recorded decisions or durable writes exist.
  has_many :price_changes, dependent: :restrict_with_exception
  has_many :price_write_intents, dependent: :restrict_with_exception

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }

  scope :recent, -> { order(created_at: :desc) }

  def self.running?
    exists?(status: "running")
  end

  def self.start!(trigger:)
    create!(status: "running", trigger: trigger.to_s, started_at: Time.current)
  rescue ActiveRecord::RecordNotUnique
    raise Pricing::RunInProgressError, "A pricing run is already in progress"
  end

  def complete!(stats)
    update!(status: "completed", finished_at: Time.current, stats: stats)
  end

  def fail!(message)
    update!(status: "failed", finished_at: Time.current, error_message: message.to_s.truncate(1000))
  end
end
