require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/plant"
require_relative "../../services/planner_tools/place_row_tool"
require_relative "../../services/planner_tools/place_column_tool"
require_relative "../../services/planner_tools/place_single_tool"
require_relative "../../services/planner_tools/place_border_tool"
require_relative "../../services/planner_tools/place_fill_tool"

class TestPlaceRowTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_places_row_of_plants
    tool = PlaceRowTool.new
    result = tool.execute(bed_name: "BB1", variety_name: "Lettuce", crop_type: "lettuce", row_y: "0", count: "5")
    plants = Plant.where(bed_id: @bed.id).all
    assert_equal 5, plants.length
    assert plants.all? { |p| p.grid_y == 0 }, "All plants should be at row 0"
    xs = plants.map(&:grid_x).sort
    assert_equal xs, xs.uniq, "No overlapping x positions"
  end

  def test_respects_custom_spacing
    tool = PlaceRowTool.new
    tool.execute(bed_name: "BB1", variety_name: "Tomato", crop_type: "tomato", row_y: "0", count: "3", spacing: "8")
    plants = Plant.where(bed_id: @bed.id).order(:grid_x).all
    assert_equal [0, 8, 16], plants.map(&:grid_x)
  end

  def test_unknown_bed
    tool = PlaceRowTool.new
    result = tool.execute(bed_name: "NOPE", variety_name: "X", crop_type: "x", row_y: "0", count: "1")
    assert_includes result, "not found"
  end
end

class TestPlaceColumnTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_places_column_of_plants
    tool = PlaceColumnTool.new
    result = tool.execute(bed_name: "BB1", variety_name: "Tomato", crop_type: "tomato", col_x: "0", count: "4")
    plants = Plant.where(bed_id: @bed.id).all
    assert_equal 4, plants.length
    assert plants.all? { |p| p.grid_x == 0 }, "All plants should be at col 0"
  end

  def test_respects_custom_spacing
    tool = PlaceColumnTool.new
    tool.execute(bed_name: "BB1", variety_name: "Tomato", crop_type: "tomato", col_x: "0", count: "3", spacing: "10")
    plants = Plant.where(bed_id: @bed.id).order(:grid_y).all
    assert_equal [0, 10, 20], plants.map(&:grid_y)
  end
end

class TestPlaceSingleTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_places_single_plant_at_exact_position
    tool = PlaceSingleTool.new
    tool.execute(bed_name: "BB1", variety_name: "Courgette", crop_type: "zucchini", grid_x: "10", grid_y: "5")
    plant = Plant.where(bed_id: @bed.id).first
    assert_equal 10, plant.grid_x
    assert_equal 5, plant.grid_y
    assert_equal "Courgette", plant.variety_name
  end

  def test_custom_size_and_quantity
    tool = PlaceSingleTool.new
    tool.execute(bed_name: "BB1", variety_name: "Radish", crop_type: "radish", grid_x: "0", grid_y: "0", grid_w: "4", grid_h: "4", quantity: "20")
    plant = Plant.where(bed_id: @bed.id).first
    assert_equal 4, plant.grid_w
    assert_equal 4, plant.grid_h
    assert_equal 20, plant.quantity
  end
end

class TestPlaceBorderTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 60, length: 60)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_places_front_border
    tool = PlaceBorderTool.new
    tool.execute(bed_name: "BB1", variety_name: "Marigold", crop_type: "flower", edges: '["front"]')
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.length > 0
    assert plants.all? { |p| p.grid_y == 0 }, "Front border should be at row 0"
  end

  def test_places_multiple_edges
    tool = PlaceBorderTool.new
    tool.execute(bed_name: "BB1", variety_name: "Onion", crop_type: "onion", edges: '["front", "back"]')
    plants = Plant.where(bed_id: @bed.id).all
    ys = plants.map(&:grid_y).uniq.sort
    assert_includes ys, 0, "Should have front row"
    max_y = @bed.grid_rows - Plant.default_grid_size("onion")[1]
    assert ys.any? { |y| y >= max_y - 1 }, "Should have back row"
  end

  def test_skips_occupied_cells
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    tool = PlaceBorderTool.new
    tool.execute(bed_name: "BB1", variety_name: "Marigold", crop_type: "flower", edges: '["front"]')
    plants = Plant.where(bed_id: @bed.id, variety_name: "Marigold").all
    assert plants.all? { |p| p.grid_x >= 6 }, "Should skip occupied cells"
  end
end

class TestPlaceFillTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 60, length: 60)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_fills_entire_bed
    tool = PlaceFillTool.new
    tool.execute(bed_name: "BB1", variety_name: "Radish", crop_type: "radish")
    plants = Plant.where(bed_id: @bed.id).all
    # radish = 2x2 cells, 12x12 grid = 6x6 = 36 plants
    assert_equal 36, plants.length
  end

  def test_fills_specific_region
    tool = PlaceFillTool.new
    tool.execute(bed_name: "BB1", variety_name: "Lettuce", crop_type: "lettuce", region: '{"from_x":0,"from_y":0,"to_x":8,"to_y":8}')
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.all? { |p| p.grid_x < 8 && p.grid_y < 8 }
  end

  def test_skips_occupied_cells
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    tool = PlaceFillTool.new
    tool.execute(bed_name: "BB1", variety_name: "Radish", crop_type: "radish")
    plants = Plant.where(bed_id: @bed.id, variety_name: "Radish").all
    plants.each do |p|
      refute(p.grid_x < 6 && p.grid_y < 6, "Should not overlap tomato at (#{p.grid_x}, #{p.grid_y})")
    end
  end
end
