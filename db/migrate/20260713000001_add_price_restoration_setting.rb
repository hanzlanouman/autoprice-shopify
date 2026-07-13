class AddPriceRestorationSetting < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :price_restoration_enabled, :boolean, null: false, default: false
  end
end
