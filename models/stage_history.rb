require_relative "../config/database"

class StageHistory < Sequel::Model
  many_to_one :plant
end
