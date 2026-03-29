require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/plant"
require_relative "../../models/succession_plan"
require_relative "../../models/task"
require_relative "../../services/planner_tools/clear_bed_tool"
require_relative "../../services/planner_tools/remove_plants_tool"
require_relative "../../services/planner_tools/move_plant_tool"
require_relative "../../services/planner_tools/update_plant_tool"
require_relative "../../services/planner_tools/delete_succession_plan_tool"

class TestClearBedTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 6, grid_y: 0, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_clears_all_plants
    tool = ClearBedTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "2"
    assert_equal 0, Plant.where(bed_id: @bed.id).count
  end

  def test_clears_sets_refresh_flag
    tool = ClearBedTool.new
    tool.execute(bed_name: "BB1")
    assert Thread.current[:planner_needs_refresh]
  end

  def test_unknown_bed_returns_error
    tool = ClearBedTool.new
    result = tool.execute(bed_name: "NOPE")
    assert_includes result, "not found"
  end
end

class TestRemovePlantsTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 6, grid_y: 0, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 0, grid_y: 6, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_remove_by_variety
    tool = RemovePlantsTool.new
    result = tool.execute(bed_name: "BB1", variety_name: "Raf")
    assert_includes result, "2"
    assert_equal 1, Plant.where(bed_id: @bed.id).count
    assert_equal "Basil", Plant.where(bed_id: @bed.id).first.variety_name
  end

  def test_remove_by_crop_type
    tool = RemovePlantsTool.new
    result = tool.execute(bed_name: "BB1", crop_type: "herb")
    assert_includes result, "1"
    assert_equal 2, Plant.where(bed_id: @bed.id).count
  end

  def test_remove_sets_refresh
    tool = RemovePlantsTool.new
    tool.execute(bed_name: "BB1", variety_name: "Raf")
    assert Thread.current[:planner_needs_refresh]
  end
end

class TestMovePlantTool < GardenTest
  def setup
    super
    @bed1 = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @bed2 = Bed.create(name: "SB1", bed_type: "raised", garden_id: @garden.id, width: 100, length: 200)
    @plant = Plant.create(garden_id: @garden.id, bed_id: @bed1.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_moves_plant_to_new_bed
    tool = MovePlantTool.new
    result = tool.execute(plant_id: @plant.id.to_s, target_bed_name: "SB1")
    assert_includes result, "SB1"
    @plant.refresh
    assert_equal @bed2.id, @plant.bed_id
  end

  def test_auto_places_on_target_bed
    Plant.create(garden_id: @garden.id, bed_id: @bed2.id, variety_name: "Basil", crop_type: "herb", grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4)
    tool = MovePlantTool.new
    tool.execute(plant_id: @plant.id.to_s, target_bed_name: "SB1")
    @plant.refresh
    assert @plant.grid_y >= 4, "Should be placed below existing plant"
  end

  def test_invalid_plant
    tool = MovePlantTool.new
    result = tool.execute(plant_id: "99999", target_bed_name: "SB1")
    assert_includes result, "not found"
  end
end

class TestUpdatePlantTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @plant = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6, quantity: 1)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_updates_grid_position
    tool = UpdatePlantTool.new
    result = tool.execute(plant_id: @plant.id.to_s, grid_x: "10", grid_y: "5")
    @plant.refresh
    assert_equal 10, @plant.grid_x
    assert_equal 5, @plant.grid_y
  end

  def test_updates_quantity
    tool = UpdatePlantTool.new
    tool.execute(plant_id: @plant.id.to_s, quantity: "3")
    @plant.refresh
    assert_equal 3, @plant.quantity
  end
end

class TestDeleteSuccessionPlanTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @plan = SuccessionPlan.create(
      garden_id: @garden.id, crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 14, season_start: Date.new(2026, 4, 1), season_end: Date.new(2026, 9, 30),
      total_planned_sowings: 5, target_beds: '["BB1"]'
    )
    Task.create(garden_id: @garden.id, title: "Sow Lettuce #1", task_type: "sow", status: "upcoming", due_date: Date.new(2026, 4, 1))
    Task.create(garden_id: @garden.id, title: "Sow Lettuce #2", task_type: "sow", status: "done", due_date: Date.new(2026, 4, 15))
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_deletes_plan_and_pending_tasks
    tool = DeleteSuccessionPlanTool.new
    result = tool.execute(crop: "Lettuce")
    assert_equal 0, SuccessionPlan.where(garden_id: @garden.id, crop: "Lettuce").count
    assert_equal 1, Task.where(garden_id: @garden.id).count
    assert_equal "done", Task.first.status
  end

  def test_unknown_crop
    tool = DeleteSuccessionPlanTool.new
    result = tool.execute(crop: "Mango")
    assert_includes result, "No succession plans found"
  end
end
