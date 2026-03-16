# config/database.rb
require "sequel"

DB = Sequel.connect(
  ENV.fetch("DATABASE_URL", "sqlite://db/garden_os.db")
)

Sequel.extension :migration
