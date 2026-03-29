require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/bed_zone"
require_relative "../../services/planner_tools/manage_zones_tool"
require_relative "../../services/planner_tools/update_bed_metadata_tool"

class TestManageZonesTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_create_zone
    tool = ManageZonesTool.new
    result = tool.execute(bed_name: "BB1", action: "create", name: "rear strip", from_x: "0", from_y: "40", to_x: "24", to_y: "48", purpose: "tall crops")
    assert_includes result, "rear strip"
    assert_equal 1, BedZone.where(bed_id: @bed.id).count
  end

  def test_list_zones
    BedZone.create(bed_id: @bed.id, name: "front edge", from_x: 0, from_y: 0, to_x: 24, to_y: 4, purpose: "border flowers", created_at: Time.now)
    tool = ManageZonesTool.new
    result = tool.execute(bed_name: "BB1", action: "list")
    assert_includes result, "front edge"
  end

  def test_delete_zone
    BedZone.create(bed_id: @bed.id, name: "temp", from_x: 0, from_y: 0, to_x: 10, to_y: 10, created_at: Time.now)
    tool = ManageZonesTool.new
    tool.execute(bed_name: "BB1", action: "delete", name: "temp")
    assert_equal 0, BedZone.where(bed_id: @bed.id).count
  end
end

class TestUpdateBedMetadataTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_updates_metadata
    tool = UpdateBedMetadataTool.new
    tool.execute(bed_name: "BB1", sun_exposure: "full", front_edge: "south", irrigation: "drip")
    @bed.refresh
    assert_equal "full", @bed.sun_exposure
    assert_equal "south", @bed.front_edge
    assert_equal "drip", @bed.irrigation
  end

  def test_unknown_bed
    tool = UpdateBedMetadataTool.new
    result = tool.execute(bed_name: "NOPE", sun_exposure: "full")
    assert_includes result, "not found"
  end
end
