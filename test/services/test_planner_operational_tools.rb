require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/plant"
require_relative "../../services/planner_tools/deduplicate_bed_tool"
require_relative "../../services/planner_tools/set_plant_notes_tool"

class TestDeduplicateBedTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_removes_duplicates_keeps_oldest
    p1 = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6, created_at: Time.now - 100)
    p2 = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 6, grid_y: 0, grid_w: 6, grid_h: 6, created_at: Time.now)
    p3 = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 0, grid_y: 6, grid_w: 4, grid_h: 4, created_at: Time.now)

    tool = DeduplicateBedTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "1"
    assert_equal 2, Plant.where(bed_id: @bed.id).count
    assert Plant[p1.id], "Oldest should survive"
    assert_nil Plant[p2.id], "Newer duplicate should be removed"
    assert Plant[p3.id], "Non-duplicate should survive"
  end

  def test_no_duplicates
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    tool = DeduplicateBedTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "No duplicates"
  end
end

class TestSetPlantNotesTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @plant = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Courgette", crop_type: "zucchini", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 8)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_set_notes_by_id
    tool = SetPlantNotesTool.new
    tool.execute(plant_id: @plant.id.to_s, notes: "Let spill over front edge")
    @plant.refresh
    assert_equal "Let spill over front edge", @plant.notes
  end

  def test_set_notes_by_bed_and_variety
    tool = SetPlantNotesTool.new
    tool.execute(bed_name: "BB1", variety_name: "Courgette", notes: "Train toward path")
    @plant.refresh
    assert_equal "Train toward path", @plant.notes
  end
end
