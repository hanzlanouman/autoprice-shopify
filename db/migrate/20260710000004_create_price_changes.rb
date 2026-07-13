class CreatePriceChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :price_changes do |t|
      t.references :pricing_run, null: false, foreign_key: true
      t.references :product, null: true, foreign_key: true
      t.string :shopify_variant_gid, null: false
      t.string :variant_title
      t.string :status, null: false            # applied / rejected / failed / skipped
      t.string :action, null: false, default: "increase" # increase / restore
      t.string :source, null: false, default: "ai"       # ai / fallback / system
      t.decimal :old_price, precision: 12, scale: 2
      t.decimal :new_price, precision: 12, scale: 2
      t.decimal :raw_recommended_price, precision: 12, scale: 2
      t.integer :inventory_level
      t.text :ai_reason
      t.string :rejection_reason

      t.datetime :created_at, null: false
    end

    add_index :price_changes, [ :product_id, :created_at ]
    add_index :price_changes, [ :shopify_variant_gid, :created_at ]
  end
end
