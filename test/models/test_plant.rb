require_relative "../test_helper"
require_relative "../../models/plant"
require_relative "../../models/stage_history"
require_relative "../../models/bed"

class TestPlant < GardenTest
  VALID_STAGES = %w[
    seed_packet pre_treating sown_indoor germinating seedling
    potted_up hardening_off planted_out producing done stratifying
  ].freeze

  def test_advance_stage
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seed_packet")
    plant.advance_stage!("sown_indoor")

    assert_equal "sown_indoor", plant.reload.lifecycle_stage
    history = StageHistory.where(plant_id: plant.id).first
    assert_equal "seed_packet", history.from_stage
    assert_equal "sown_indoor", history.to_stage
  end

  def test_advance_stage_rejects_invalid
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seed_packet")
    assert_raises(ArgumentError) { plant.advance_stage!("bogus") }
  end

  def test_days_in_stage
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "germinating")
    StageHistory.create(plant_id: plant.id, to_stage: "germinating",
                        changed_at: Time.now - (5 * 86400))
    assert_equal 5, plant.days_in_stage
  end
end
