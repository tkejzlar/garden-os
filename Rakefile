# Rakefile
require_relative "config/database"

namespace :db do
  desc "Run migrations"
  task :migrate do
    Sequel::Migrator.run(DB, "db/migrations")
    puts "Migrations complete."
  end

  desc "Rollback last migration"
  task :rollback do
    Sequel::Migrator.run(DB, "db/migrations", target: 0)
    puts "Rollback complete."
  end

  desc "Seed variety data"
  task :seed do
    require_relative "db/seeds/seed_varieties"
    puts "Seed data loaded."
  end
end
