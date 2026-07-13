class AddStaleAtToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :stale_at, :datetime
    add_index :products, :stale_at
  end
end
