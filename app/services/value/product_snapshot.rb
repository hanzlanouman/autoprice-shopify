module Value
  # Immutable view of a product plus its variant snapshots.
  ProductSnapshot = Data.define(
    :gid,
    :title,
    :product_type,
    :vendor,
    :status,
    :gift_card,
    :variants # Array<Value::VariantSnapshot>
  )
end
