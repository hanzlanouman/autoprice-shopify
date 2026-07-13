class CreatePriceWriteIntents < ActiveRecord::Migration[8.1]
  def change
    create_table :price_write_intents do |t|
      t.references :pricing_run, null: false, foreign_key: true
      t.references :product, null: true, foreign_key: true
      t.string :product_gid, null: false
      t.string :shopify_variant_gid, null: false
      t.string :variant_title
      t.string :status, null: false, default: "pending"
      t.string :action, null: false
      t.string :source, null: false
      t.decimal :expected_old_price, precision: 12, scale: 2, null: false
      t.decimal :target_price, precision: 12, scale: 2, null: false
      t.integer :inventory_level
      t.text :reason
      t.string :resolution_reason
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :price_write_intents,
              %i[pricing_run_id shopify_variant_gid],
              unique: true,
              name: "index_write_intents_on_run_and_variant"
    add_index :price_write_intents,
              %i[status shopify_variant_gid],
              name: "index_write_intents_on_status_and_variant"
  end
end
