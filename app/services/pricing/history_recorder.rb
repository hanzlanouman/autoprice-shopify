module Pricing
  # Stage 6: writes one append-only price_changes row per planned change —
  # applied, rejected, failed, and skipped alike — so every decision is
  # auditable (NFR4). insert_all keeps it a single write.
  class HistoryRecorder
    def call(run, planned_changes)
      now = Time.current
      rows = planned_changes.map do |c|
        {
          pricing_run_id: run.id,
          product_id: c.product_id,
          shopify_variant_gid: c.variant_gid,
          variant_title: c.variant_title,
          status: c.status.to_s,
          action: c.action,
          source: c.source,
          old_price: c.old_price,
          new_price: c.new_price,
          raw_recommended_price: c.raw_recommended_price,
          inventory_level: c.inventory_level,
          ai_reason: c.ai_reason,
          rejection_reason: c.rejection_reason,
          created_at: now
        }
      end
      PriceChange.insert_all(rows, unique_by: :index_price_changes_on_run_and_variant) if rows.any?
      rows.size
    end
  end
end
