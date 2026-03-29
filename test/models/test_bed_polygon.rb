require_relative "../test_helper"
require_relative "../../models/bed"

class TestBedPolygon < GardenTest
  def test_rectangular_bed_always_true
    bed = Bed.create(name: "R1", bed_type: "raised", garden_id: @garden.id, width: 100, length: 100)
    assert bed.point_in_polygon?(5, 5)
    assert bed.point_in_polygon?(0, 0)
  end

  def test_triangle_inside
    # Triangle: (0,0), (100,0), (50,100) — in canvas coords
    bed = Bed.create(name: "T1", bed_type: "raised", garden_id: @garden.id,
      canvas_points: [[0, 0], [100, 0], [50, 100]].to_json)
    # Center of triangle should be inside (grid coords: 50/5=10, 33/5≈6)
    assert bed.point_in_polygon?(10, 6)
  end

  def test_triangle_outside
    bed = Bed.create(name: "T2", bed_type: "raised", garden_id: @garden.id,
      canvas_points: [[0, 0], [100, 0], [50, 100]].to_json)
    # Top-right corner of bounding box is outside the triangle
    assert_equal false, bed.point_in_polygon?(19, 1)
  end
end
