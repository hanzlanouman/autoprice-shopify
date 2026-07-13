# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_13_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "price_changes", force: :cascade do |t|
    t.string "action", default: "increase", null: false
    t.text "ai_reason"
    t.datetime "created_at", null: false
    t.integer "inventory_level"
    t.decimal "new_price", precision: 12, scale: 2
    t.decimal "old_price", precision: 12, scale: 2
    t.bigint "pricing_run_id", null: false
    t.bigint "product_id"
    t.decimal "raw_recommended_price", precision: 12, scale: 2
    t.string "rejection_reason"
    t.string "shopify_variant_gid", null: false
    t.string "source", default: "ai", null: false
    t.string "status", null: false
    t.string "variant_title"
    t.index ["pricing_run_id", "shopify_variant_gid"], name: "index_price_changes_on_run_and_variant", unique: true
    t.index ["pricing_run_id"], name: "index_price_changes_on_pricing_run_id"
    t.index ["product_id", "created_at"], name: "index_price_changes_on_product_id_and_created_at"
    t.index ["product_id", "id"], name: "index_price_changes_on_product_and_id"
    t.index ["product_id"], name: "index_price_changes_on_product_id"
    t.index ["shopify_variant_gid", "created_at"], name: "index_price_changes_on_shopify_variant_gid_and_created_at"
    t.index ["shopify_variant_gid", "id"], name: "index_price_changes_on_variant_and_id"
    t.index ["status", "id"], name: "index_price_changes_on_status_and_id"
    t.check_constraint "status::text <> 'applied'::text OR action::text <> 'increase'::text OR new_price >= old_price", name: "price_changes_increase_not_lower"
    t.check_constraint "status::text <> 'applied'::text OR action::text <> 'restore'::text OR new_price <= old_price", name: "price_changes_restore_not_higher"
    t.check_constraint "status::text <> 'applied'::text OR old_price IS NOT NULL AND new_price IS NOT NULL", name: "price_changes_applied_prices_present"
  end

  create_table "price_write_intents", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.decimal "expected_old_price", precision: 12, scale: 2, null: false
    t.integer "inventory_level"
    t.bigint "pricing_run_id", null: false
    t.string "product_gid", null: false
    t.bigint "product_id"
    t.text "reason"
    t.string "resolution_reason"
    t.datetime "resolved_at"
    t.string "shopify_variant_gid", null: false
    t.string "source", null: false
    t.string "status", default: "pending", null: false
    t.decimal "target_price", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.string "variant_title"
    t.index ["pricing_run_id", "shopify_variant_gid"], name: "index_write_intents_on_run_and_variant", unique: true
    t.index ["pricing_run_id"], name: "index_price_write_intents_on_pricing_run_id"
    t.index ["product_id"], name: "index_price_write_intents_on_product_id"
    t.index ["status", "shopify_variant_gid"], name: "index_write_intents_on_status_and_variant"
  end

  create_table "pricing_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "started_at"
    t.jsonb "stats", default: {}, null: false
    t.string "status", default: "running", null: false
    t.string "trigger", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_pricing_runs_on_created_at"
    t.index ["status"], name: "index_pricing_runs_single_running", unique: true, where: "((status)::text = 'running'::text)"
  end

  create_table "products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "gift_card", default: false, null: false
    t.string "product_type"
    t.string "shopify_gid", null: false
    t.datetime "stale_at"
    t.string "status", default: "active", null: false
    t.datetime "synced_at"
    t.string "title", default: "", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variants", default: [], null: false
    t.string "vendor"
    t.index ["shopify_gid"], name: "index_products_on_shopify_gid", unique: true
    t.index ["stale_at"], name: "index_products_on_stale_at"
  end

  create_table "settings", force: :cascade do |t|
    t.text "ai_behavior_prompt"
    t.boolean "auto_pricing_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "fallback_pricing_enabled", default: false, null: false
    t.integer "inventory_threshold", default: 10, null: false
    t.decimal "max_price_percentage", precision: 12, scale: 2, default: "150.0", null: false
    t.datetime "next_run_at"
    t.boolean "price_restoration_enabled", default: false, null: false
    t.string "review_frequency", default: "daily", null: false
    t.integer "singleton_key", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["singleton_key"], name: "index_settings_on_singleton_key", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  add_foreign_key "price_changes", "pricing_runs"
  add_foreign_key "price_changes", "products"
  add_foreign_key "price_write_intents", "pricing_runs"
  add_foreign_key "price_write_intents", "products"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
