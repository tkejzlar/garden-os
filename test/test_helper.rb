# test/test_helper.rb
ENV["RACK_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite://db/garden_os_test.db"

require "minitest/autorun"
require "rack/test"
require_relative "../config/database"

Sequel::Migrator.run(DB, "db/migrations") if Dir["db/migrations/*.rb"].any?

class GardenTest < Minitest::Test
  include Rack::Test::Methods

  def app
    GardenApp
  end

  def setup
    # Clean all tables before each test
    DB.tables.each { |t| DB[t].delete unless t == :schema_migrations }
  end
end
