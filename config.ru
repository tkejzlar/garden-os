# config.ru
require_relative "app"

# Run migrations on startup
Sequel::Migrator.run(DB, "db/migrations")

# Start background scheduler (not in test)
unless ENV["RACK_ENV"] == "test"
  require_relative "services/scheduler"
  GardenScheduler.start!
end

run GardenApp
