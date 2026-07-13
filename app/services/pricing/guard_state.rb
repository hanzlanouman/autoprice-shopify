module Pricing
  # Pure helpers for updating the cached per-variant guard state after a price
  # write. Both the normal apply path and crash reconciliation use this exact
  # code so recovery cannot invent different baseline semantics.
  module GuardState
    module_function

    def apply(variant, action:, old_price:, new_price:, inventory_level:, at: Time.current)
      data = variant.with_indifferent_access
      if action == "restore"
        data.merge(
          "price" => Money.format(new_price),
          "original_price" => nil,
          "last_written_price" => Money.format(new_price),
          "last_adjusted_at" => nil,
          "inventory_at_last_adjustment" => nil
        )
      else
        data.merge(
          "price" => Money.format(new_price),
          "last_written_price" => Money.format(new_price),
          "last_adjusted_at" => at.iso8601,
          "inventory_at_last_adjustment" => inventory_level,
          "original_price" => data[:original_price].presence || Money.format(old_price)
        )
      end
    end
  end
end
