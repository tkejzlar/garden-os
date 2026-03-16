require_relative "../config/database"
require_relative "stage_history"
require_relative "harvest"

class Plant < Sequel::Model
  many_to_one :slot
  many_to_one :indoor_station
  one_to_many :stage_histories
  one_to_many :harvests
  many_to_many :tasks

  LIFECYCLE_STAGES = %w[
    seed_packet pre_treating sown_indoor germinating seedling
    potted_up hardening_off planted_out producing done stratifying
  ].freeze

  def advance_stage!(new_stage, note: nil)
    raise ArgumentError, "Invalid stage: #{new_stage}" unless LIFECYCLE_STAGES.include?(new_stage)

    old_stage = lifecycle_stage
    DB.transaction do
      update(lifecycle_stage: new_stage, updated_at: Time.now)
      update(sow_date: Date.today) if new_stage == "sown_indoor" && sow_date.nil?
      update(germination_date: Date.today) if new_stage == "germinating" && germination_date.nil?
      update(transplant_date: Date.today) if new_stage == "planted_out" && transplant_date.nil?

      StageHistory.create(
        plant_id: id,
        from_stage: old_stage,
        to_stage: new_stage,
        note: note,
        changed_at: Time.now
      )
    end
    self
  end

  def days_in_stage
    last_change = StageHistory.where(plant_id: id, to_stage: lifecycle_stage)
                              .order(Sequel.desc(:changed_at)).first
    return 0 unless last_change

    ((Time.now - last_change.changed_at) / 86400).to_i
  end
end
