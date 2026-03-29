require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/bed_zone"
require_relative "../../models/plant"
require_relative "../../services/planner_tools/place_in_zone_tool"

class TestPlaceInZoneTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @zone = BedZone.create(bed_id: @bed.id, name: "rear", from_x: 0, from_y: 36, to_x: 24, to_y: 48, purpose: "tall crops", created_at: Time.now)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_fill_zone
    tool = PlaceInZoneTool.new
    tool.execute(bed_name: "BB1", zone_name: "rear", variety_name: "Tomato", crop_type: "tomato", strategy: "fill")
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.length > 0
    plants.each do |p|
      assert p.grid_x >= 0 && p.grid_x < 24, "x=#{p.grid_x} should be in zone"
      assert p.grid_y >= 36 && p.grid_y < 48, "y=#{p.grid_y} should be in zone"
    end
  end

  def test_center_zone
    tool = PlaceInZoneTool.new
    tool.execute(bed_name: "BB1", zone_name: "rear", variety_name: "Squash", crop_type: "squash", strategy: "center")
    plants = Plant.where(bed_id: @bed.id).all
    assert_equal 1, plants.length
  end

  def test_row_in_zone
    tool = PlaceInZoneTool.new
    tool.execute(bed_name: "BB1", zone_name: "rear", variety_name: "Lettuce", crop_type: "lettuce", strategy: "row")
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.length > 0
    ys = plants.map(&:grid_y).uniq
    assert_equal 1, ys.length, "All plants should be in same row"
  end

  def test_unknown_zone
    tool = PlaceInZoneTool.new
    result = tool.execute(bed_name: "BB1", zone_name: "nope", variety_name: "X", crop_type: "x", strategy: "fill")
    assert_includes result, "not found"
  end
end

require_relative "../../services/planner_tools/align_plants_tool"

class TestAlignPlantsTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 2, grid_y: 5, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Pepper", crop_type: "pepper", grid_x: 10, grid_y: 3, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 7, grid_y: 20, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_align_left
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "align-left")
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.all? { |p| p.grid_x == 2 }, "All should align to leftmost x=2"
  end

  def test_align_top
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "align-top")
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.all? { |p| p.grid_y == 3 }, "All should align to topmost y=3"
  end

  def test_distribute_h
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "distribute-h")
    plants = Plant.where(bed_id: @bed.id).order(:grid_x).all
    xs = plants.map(&:grid_x)
    gaps = xs.each_cons(2).map { |a, b| b - a }
    assert gaps.length >= 1
    assert gaps.uniq.length <= 2, "Gaps should be roughly equal (rounding allowed)"
  end

  def test_filter_by_crop_type
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "align-left", filter_crop_type: "tomato")
    tomato = Plant.where(bed_id: @bed.id, crop_type: "tomato").first
    pepper = Plant.where(bed_id: @bed.id, crop_type: "pepper").first
    assert_equal 2, tomato.grid_x, "Tomato unchanged (already at 2)"
    assert_equal 10, pepper.grid_x, "Pepper should NOT be affected"
  end

  def test_compact
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "compact")
    plants = Plant.where(bed_id: @bed.id).order(:grid_y, :grid_x).all
    assert plants.first.grid_x == 0 || plants.first.grid_y == 0, "Should pack toward origin"
  end
end

require_relative "../../services/planner_tools/group_edit_tool"

class TestGroupEditTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 5, grid_y: 10, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 15, grid_y: 10, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_group_move
    tool = GroupEditTool.new
    tool.execute(bed_name: "BB1", action: "move", filter_crop_type: "tomato", dx: "3", dy: "-2")
    tomatoes = Plant.where(bed_id: @bed.id, crop_type: "tomato").all
    assert_equal [8, 18], tomatoes.map(&:grid_x).sort
    assert tomatoes.all? { |p| p.grid_y == 8 }
    basil = Plant.where(bed_id: @bed.id, crop_type: "herb").first
    assert_equal 0, basil.grid_x, "Basil should not move"
  end

  def test_group_resize
    tool = GroupEditTool.new
    tool.execute(bed_name: "BB1", action: "resize", filter_crop_type: "tomato", grid_w: "8", grid_h: "8")
    tomatoes = Plant.where(bed_id: @bed.id, crop_type: "tomato").all
    assert tomatoes.all? { |p| p.grid_w == 8 && p.grid_h == 8 }
  end
end

require_relative "../../services/planner_tools/place_band_tool"

class TestPlaceBandTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_horizontal_band
    tool = PlaceBandTool.new
    tool.execute(bed_name: "BB1", variety_name: "Radish", crop_type: "radish", orientation: "horizontal", position: "10", thickness: "4", quantity: "50")
    plant = Plant.where(bed_id: @bed.id).first
    assert_equal 0, plant.grid_x
    assert_equal 10, plant.grid_y
    assert_equal 24, plant.grid_w  # full bed width (120cm / 5cm = 24 cols)
    assert_equal 4, plant.grid_h
    assert_equal 50, plant.quantity
  end

  def test_vertical_band
    tool = PlaceBandTool.new
    tool.execute(bed_name: "BB1", variety_name: "Carrot", crop_type: "carrot", orientation: "vertical", position: "5", thickness: "3", quantity: "30")
    plant = Plant.where(bed_id: @bed.id).first
    assert_equal 5, plant.grid_x
    assert_equal 0, plant.grid_y
    assert_equal 3, plant.grid_w
    assert_equal 48, plant.grid_h  # full bed height (240cm / 5cm = 48 rows)
  end
end
