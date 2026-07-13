# Single source of the pricing-run JSON shape (docs/ARCHITECTURE.md). Pass
# include_changes: true for the run detail view.
class PricingRunSerializer
  def initialize(run, include_changes: false)
    @run = run
    @include_changes = include_changes
  end

  def as_json(*)
    json = {
      id: @run.id,
      status: @run.status,
      trigger: @run.trigger,
      started_at: @run.started_at&.iso8601,
      finished_at: @run.finished_at&.iso8601,
      stats: @run.stats,
      error_message: @run.error_message
    }
    if @include_changes
      json[:price_changes] = @run.price_changes.includes(:product).recent
                                 .map { |pc| PriceChangeSerializer.new(pc).as_json }
    end
    json
  end
end
