module Value
  # The unit that flows through validation → apply → history. Immutable; stages
  # derive new copies with `.with(...)`. `status` is :pending for changes headed
  # to the applier (which resolves them to applied/failed); rejected and skipped
  # items carry their final status from the start.
  PlannedChange = Data.define(
    :product_gid,
    :product_id,
    :variant_gid,
    :variant_title,
    :status,               # :pending / "applied" / "failed" / "rejected" / "skipped"
    :action,               # "increase" / "restore"
    :source,               # "ai" / "fallback" / "system"
    :old_price,            # BigDecimal or nil
    :new_price,            # BigDecimal or nil
    :raw_recommended_price, # BigDecimal or nil
    :inventory_level,      # Integer or nil
    :ai_reason,            # String or nil
    :rejection_reason      # String or nil
  ) do
    def pending?
      status == :pending
    end
  end
end
