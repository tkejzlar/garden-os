require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/plant"
require_relative "../../services/planner_tools/copy_layout_tool"

class TestCopyLayoutTool < GardenTest
  def setup
    super
    @bed1 = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @bed2 = Bed.create(name: "BB2", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed1.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed1.id, variety_name: "Basil", crop_type: "herb", grid_x: 10, grid_y: 10, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_copy_layout
    tool = CopyLayoutTool.new
    tool.execute(source_bed: "BB1", target_bed: "BB2", mode: "copy")
    target_plants = Plant.where(bed_id: @bed2.id).all
    assert_equal 2, target_plants.length
    assert target_plants.any? { |p| p.variety_name == "Tomato" && p.grid_x == 0 }
    assert target_plants.any? { |p| p.variety_name == "Basil" && p.grid_x == 10 }
  end

  def test_mirror_horizontal
    tool = CopyLayoutTool.new
    tool.execute(source_bed: "BB1", target_bed: "BB2", mode: "mirror-h")
    target_plants = Plant.where(bed_id: @bed2.id).all
    tomato = target_plants.find { |p| p.variety_name == "Tomato" }
    # BB2 has 24 cols, tomato is 6 wide at x=0 → mirrored x = 24 - 0 - 6 = 18
    assert_equal 18, tomato.grid_x
  end

  def test_mirror_vertical
    tool = CopyLayoutTool.new
    tool.execute(source_bed: "BB1", target_bed: "BB2", mode: "mirror-v")
    target_plants = Plant.where(bed_id: @bed2.id).all
    tomato = target_plants.find { |p| p.variety_name == "Tomato" }
    # BB2 has 48 rows, tomato is 6 tall at y=0 → mirrored y = 48 - 0 - 6 = 42
    assert_equal 42, tomato.grid_y
  end

  def test_clear_target
    Plant.create(garden_id: @garden.id, bed_id: @bed2.id, variety_name: "Old", crop_type: "flower", grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4)
    tool = CopyLayoutTool.new
    tool.execute(source_bed: "BB1", target_bed: "BB2", mode: "copy", clear_target: "true")
    target_plants = Plant.where(bed_id: @bed2.id).all
    assert_equal 2, target_plants.length
    assert target_plants.none? { |p| p.variety_name == "Old" }
  end
end

require_relative "../../services/planner_tools/get_empty_space_tool"

class TestGetEmptySpaceTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 60, length: 60)
    # 12x12 grid. Place a 6x6 tomato in top-left → 75% empty
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_reports_empty_space
    tool = GetEmptySpaceTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "75%"
    assert_includes result, "108"  # 144 total - 36 occupied = 108 empty
  end

  def test_fully_empty_bed
    Plant.where(bed_id: @bed.id).all.each(&:destroy)
    tool = GetEmptySpaceTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "100%"
  end
end
