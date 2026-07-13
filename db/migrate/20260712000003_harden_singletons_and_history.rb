class HardenSingletonsAndHistory < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :singleton_key, :integer, null: false, default: 1
    add_index :settings, :singleton_key, unique: true

    add_index :price_changes,
              %i[pricing_run_id shopify_variant_gid],
              unique: true,
              name: "index_price_changes_on_run_and_variant"
    add_index :price_changes, %i[status id]
    add_index :price_changes, %i[shopify_variant_gid id], name: "index_price_changes_on_variant_and_id"
    add_index :price_changes, %i[product_id id], name: "index_price_changes_on_product_and_id"

    add_check_constraint :price_changes,
                         "status <> 'applied' OR (old_price IS NOT NULL AND new_price IS NOT NULL)",
                         name: "price_changes_applied_prices_present"
    add_check_constraint :price_changes,
                         "status <> 'applied' OR action <> 'increase' OR new_price >= old_price",
                         name: "price_changes_increase_not_lower"
    add_check_constraint :price_changes,
                         "status <> 'applied' OR action <> 'restore' OR new_price <= old_price",
                         name: "price_changes_restore_not_higher"
  end
end
