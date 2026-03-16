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

namespace :catalog do
  desc "Scrape all seed suppliers"
  task :scrape do
    require_relative "config/database"
    Sequel::Migrator.run(DB, "db/migrations")
    require_relative "models/seed_catalog_entry"
    require_relative "services/catalog_scraper"

    CatalogScraper.scrape_all!
  end

  desc "Scrape a single supplier (e.g. rake catalog:scrape_one[reinsaat])"
  task :scrape_one, [:supplier] do |t, args|
    require_relative "config/database"
    Sequel::Migrator.run(DB, "db/migrations")
    require_relative "models/seed_catalog_entry"
    require_relative "services/catalog_scraper"

    CatalogScraper.scrape_supplier!(args[:supplier])
  end

  desc "Show catalog stats"
  task :stats do
    require_relative "config/database"
    Sequel::Migrator.run(DB, "db/migrations")
    require_relative "models/seed_catalog_entry"

    total = SeedCatalogEntry.count
    by_supplier = SeedCatalogEntry.group_and_count(:supplier).all
    puts "Seed catalog: #{total} varieties"
    by_supplier.each { |r| puts "  #{r[:supplier]}: #{r[:count]}" }
  end
end
