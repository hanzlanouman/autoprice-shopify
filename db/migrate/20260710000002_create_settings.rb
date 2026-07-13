class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.integer :inventory_threshold, null: false, default: 10
      t.decimal :max_price, precision: 12, scale: 2, null: false, default: "150.0"
      t.string :review_frequency, null: false, default: "daily"
      t.text :ai_behavior_prompt
      t.datetime :next_run_at
      t.boolean :auto_pricing_enabled, null: false, default: false
      t.boolean :fallback_pricing_enabled, null: false, default: false

      t.timestamps
    end
  end
end
