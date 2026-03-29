require_relative "../config/database"

class BedZone < Sequel::Model(:bed_zones)
  many_to_one :bed
end
