ENV["RACK_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite://db/garden_os_test.db"

require "minitest/autorun"
require "rack/test"
require_relative "../config/database"

if Dir["db/migrations/*.rb"].any?
  Sequel::Migrator.run(DB, "db/migrations", allow_missing_migration_files: true)
end

require_relative "../models/garden"

class GardenTest < Minitest::Test
  include Rack::Test::Methods

  def app
    GardenApp
  end

  def setup
    DB.tables.each { |t| DB[t].delete unless [:schema_migrations, :schema_info].include?(t) }
    @garden = Garden.create(name: "Test Garden", created_at: Time.now)
    set_cookie "garden_id=#{@garden.id}"
  end
end
