class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :shopify_gid, null: false
      t.string :title, null: false, default: ""
      t.string :product_type
      t.string :vendor
      t.string :status, null: false, default: "active"
      t.boolean :gift_card, null: false, default: false
      t.datetime :synced_at
      # Per-variant snapshot: gid, title, price, inventory_quantity, tracked,
      # original_price, last_adjusted_at, inventory_at_last_adjustment,
      # last_written_price. Dashboard/guard state only — never a pricing input.
      t.jsonb :variants, null: false, default: []

      t.timestamps
    end

    add_index :products, :shopify_gid, unique: true
  end
end
