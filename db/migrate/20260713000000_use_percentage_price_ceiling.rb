class UsePercentagePriceCeiling < ActiveRecord::Migration[8.1]
  # The original value 150 maps directly to "150% of base", preserving the
  # assignment example (100 -> 150) while making the ceiling product-relative.
  def change
    rename_column :settings, :max_price, :max_price_percentage
  end
end
