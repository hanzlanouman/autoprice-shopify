class CreatePricingRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :pricing_runs do |t|
      t.string :status, null: false, default: "running"
      t.string :trigger, null: false, default: "manual"
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :stats, null: false, default: {}
      t.text :error_message

      t.timestamps
    end

    # At most one run may be "running" at a time, alongside the advisory lock in
    # PricingRunJob.
    add_index :pricing_runs, :status, unique: true, where: "status = 'running'", name: "index_pricing_runs_single_running"
    add_index :pricing_runs, :created_at
  end
end
