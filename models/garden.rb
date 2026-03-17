require_relative "../config/database"

class Garden < Sequel::Model
  one_to_many :beds
  one_to_many :plants
  one_to_many :tasks
  one_to_many :succession_plans
  one_to_many :planner_messages
  one_to_many :advisories
end
