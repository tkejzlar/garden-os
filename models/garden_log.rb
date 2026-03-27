require_relative "../config/database"

class GardenLog < Sequel::Model
  many_to_one :garden
end
