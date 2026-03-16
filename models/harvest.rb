require_relative "../config/database"

class Harvest < Sequel::Model
  QUANTITIES = %w[small medium large huge].freeze

  many_to_one :plant

  def validate
    super
    errors.add(:quantity, "must be one of: #{QUANTITIES.join(', ')}") unless QUANTITIES.include?(quantity)
    errors.add(:date, "is required") if date.nil?
    errors.add(:plant_id, "is required") if plant_id.nil?
  end
end
