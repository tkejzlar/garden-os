# test/models/test_bed.rb
require_relative "../test_helper"
require_relative "../../models/bed"

class TestBedModel < GardenTest

  def test_canvas_points_array_nil_when_unset
    bed = Bed.create(name: "B1", bed_type: "raised")
    assert_equal [], bed.canvas_points_array
  end

  def test_canvas_points_array_roundtrip
    pts = [[10, 20], [30, 40], [50, 10]]
    bed = Bed.create(name: "B2", bed_type: "raised")
    bed.canvas_points_array = pts
    bed.save
    bed.reload
    assert_equal pts, bed.canvas_points_array
  end

  def test_placed_false_when_canvas_x_nil
    bed = Bed.create(name: "B3", bed_type: "raised")
    refute bed.placed?
  end

  def test_placed_true_when_canvas_x_set
    bed = Bed.create(name: "B4", bed_type: "raised",
                     canvas_x: 10.0, canvas_y: 20.0)
    assert bed.placed?
  end

  def test_polygon_false_for_rectangle
    bed = Bed.create(name: "B5", bed_type: "raised")
    refute bed.polygon?
  end

  def test_polygon_true_when_points_set
    bed = Bed.create(name: "B6", bed_type: "raised")
    bed.canvas_points_array = [[0, 0], [10, 0], [10, 10]]
    bed.save
    assert bed.polygon?
  end
end
