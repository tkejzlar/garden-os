require_relative "../config/database"

class Bed < Sequel::Model
  one_to_many :rows
end

class Row < Sequel::Model
  many_to_one :bed
  one_to_many :slots
end

class Slot < Sequel::Model
  many_to_one :row
  one_to_many :plants
end

class Arch < Sequel::Model; end

class IndoorStation < Sequel::Model; end
