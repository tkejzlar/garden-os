require_relative "../test_helper"
require_relative "../../app"

class TestBeds < GardenTest
  def test_beds_index
    Bed.create(name: "BB1", bed_type: "raised")
    get "/beds"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "BB1"
  end

  def test_bed_show_with_plants
    bed = Bed.create(name: "BB1", bed_type: "raised")
    row = Row.create(bed_id: bed.id, name: "Row A", position: 1)
    slot = Slot.create(row_id: row.id, name: "Pos 1", position: 1)
    Plant.create(variety_name: "Raf", crop_type: "tomato", slot_id: slot.id)
    get "/beds/#{bed.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Raf"
  end

  def test_beds_api
    Bed.create(name: "BB1", bed_type: "raised")
    get "/api/beds"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 1, data.length
  end
end
