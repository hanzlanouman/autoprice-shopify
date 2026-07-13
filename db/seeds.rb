# Seeds a demo-ready state so the dashboard is never blank on first boot.
# Idempotent: creates the settings singleton and, if there are no products yet,
# populates the local cache with the demo catalogue (no Shopify needed).
Setting.instance

if Product.count.zero?
  require "rake"
  Rails.application.load_tasks
  Rake::Task["demo:seed_local"].invoke
  puts "Seeded demo products."
end
