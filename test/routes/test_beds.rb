require_relative "../test_helper"
require_relative "../../app"

class TestBeds < GardenTest
  def test_beds_index_redirects_to_garden
    Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id)
    get "/beds"
    assert_equal 301, last_response.status
    assert_includes last_response.headers["Location"], "/garden"
  end

  def test_bed_show_with_plants
    bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id)
    Plant.create(
      variety_name: "Raf", crop_type: "tomato",
      bed_id: bed.id, grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4, quantity: 1,
      lifecycle_stage: "seedling", garden_id: @garden.id
    )
    get "/beds/#{bed.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Raf"
  end

  def test_beds_api
    bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id)
    Plant.create(
      variety_name: "Cherry", crop_type: "tomato",
      bed_id: bed.id, grid_x: 0, grid_y: 0, grid_w: 2, grid_h: 2, quantity: 3,
      lifecycle_stage: "seedling", garden_id: @garden.id
    )
    get "/api/beds"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 1, data.length
    assert_equal 1, data[0]["plants"].length
    assert_equal "Cherry", data[0]["plants"][0]["variety_name"]
  end
end
