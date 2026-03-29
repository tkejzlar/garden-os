ENV["RACK_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite://db/garden_os_test.db"

require "minitest/autorun"
require "rack/test"
require_relative "../config/database"
require_relative "../app"

if Dir["db/migrations/*.rb"].any?
  Sequel::Migrator.run(DB, "db/migrations", allow_missing_migration_files: true)
  # Reset cached column schema so models pick up any newly added columns
  ObjectSpace.each_object(Class).select { |c| c < Sequel::Model }.each { |m| m.instance_variable_set(:@db_schema, nil) rescue nil }
end

require_relative "../models/garden"

class GardenTest < Minitest::Test
  include Rack::Test::Methods

  def app
    GardenApp
  end

  def setup
    DB.run("PRAGMA foreign_keys = OFF")
    DB.tables.each { |t| DB[t].delete unless [:schema_migrations, :schema_info].include?(t) }
    DB.run("PRAGMA foreign_keys = ON")
    @garden = Garden.create(name: "Test Garden", created_at: Time.now)
    set_cookie "garden_id=#{@garden.id}"
  end
end
