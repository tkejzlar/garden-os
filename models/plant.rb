require_relative "../config/database"
require_relative "stage_history"
require_relative "harvest"

class Plant < Sequel::Model
  many_to_one :garden
  many_to_one :bed
  many_to_one :indoor_station
  one_to_many :stage_histories
  one_to_many :harvests
  one_to_many :photos
  many_to_many :tasks

  # Default grid sizes per crop type (in 10cm cells)
  CROP_SPACING = {
    "tomato"    => [4, 4],  # 40×40cm
    "pepper"    => [3, 3],  # 30×30cm
    "eggplant"  => [4, 4],  # 40×40cm
    "lettuce"   => [2, 2],  # 20×20cm
    "spinach"   => [2, 2],
    "chard"     => [3, 3],
    "kale"      => [3, 3],
    "herb"      => [2, 2],  # 20×20cm
    "basil"     => [2, 2],
    "cucumber"  => [3, 4],  # 30×40cm
    "squash"    => [4, 4],
    "zucchini"  => [4, 4],
    "melon"     => [4, 4],
    "flower"    => [2, 2],
    "radish"    => [1, 1],  # 10×10cm (dense)
    "carrot"    => [1, 1],
    "onion"     => [1, 1],
    "bean"      => [2, 3],
    "pea"       => [2, 3],
  }.freeze

  def self.default_grid_size(crop_type)
    CROP_SPACING[crop_type.to_s.downcase] || [2, 2]
  end

  LIFECYCLE_STAGES = %w[
    seed_packet pre_treating sown_indoor germinating seedling
    potted_up hardening_off planted_out producing done stratifying
  ].freeze

  STAGE_INSTRUCTIONS = {
    "seed_packet"   => "Seed is stored. Check sow-by date. Plan your sowing schedule based on crop type and last frost date (~May 13 in Prague).",
    "pre_treating"  => "Soak seeds 12-24h in lukewarm water, or place in damp paper towel in fridge (stratification) for seeds that need cold treatment (lavender, some herbs). Check daily.",
    "sown_indoor"   => "Fill modules/trays with seed compost, sow at correct depth (usually 2× seed diameter). Label clearly. Place on heat mat if needed (peppers 28°C, tomatoes 22°C). Keep moist but not wet.",
    "germinating"   => "Keep warm and moist. Check daily for emergence. Remove covers as soon as first seedlings appear. Move to light immediately when they emerge.",
    "seedling"      => "Ensure 12-16h of light (grow lights or bright windowsill). Water from below. Feed with half-strength liquid fertilizer weekly once true leaves appear. Thin if overcrowded.",
    "potted_up"     => "Move to individual 9cm pots when first true leaves are well developed. Handle by leaves, not stems. Use potting compost. Water in well. Keep under lights.",
    "hardening_off" => "Start 7-10 days before transplant date. Day 1-3: 2-3h outside in shade. Day 4-6: half day, some sun. Day 7-10: full day outside, bring in at night if frost risk. Watch forecast!",
    "planted_out"   => "Transplant after last frost (May 15+ in Prague). Water deeply. Mulch around base. Stake tomatoes immediately. Protect from slugs. Don't fertilize for first week.",
    "producing"     => "Harvest regularly to encourage more production. Feed weekly with tomato fertilizer (for fruiting crops). Water consistently — irregular watering causes blossom end rot.",
    "done"          => "Remove spent plants. Compost healthy material. Note variety performance for next season. Save seeds if open-pollinated.",
    "stratifying"   => "Seeds in damp sand/vermiculite in the fridge (2-4°C) for 2-8 weeks depending on species. Check weekly for moisture. Some seeds need light exposure too."
  }.freeze

  def stage_instruction
    STAGE_INSTRUCTIONS[lifecycle_stage]
  end

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
