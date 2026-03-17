require_relative "../config/database"

class Task < Sequel::Model
  many_to_one :garden
  many_to_many :plants, join_table: :tasks_plants
  many_to_many :beds, join_table: :tasks_beds

  TYPES = %w[sow transplant feed water harvest build prep check order].freeze
  PRIORITIES = %w[must should could].freeze
  STATUSES = %w[upcoming ready done skipped deferred].freeze

  def complete!
    update(status: "done", completed_at: Time.now, updated_at: Time.now)
  end

  def conditions_hash
    conditions ? JSON.parse(conditions) : {}
  end
end
