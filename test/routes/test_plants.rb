require_relative "../test_helper"
require_relative "../../app"

class TestPlants < GardenTest
  def test_plants_index
    Plant.create(variety_name: "Raf", crop_type: "tomato")
    get "/plants"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Raf"
  end

  def test_plants_show
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato")
    get "/plants/#{plant.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Raf"
  end

  def test_advance_stage
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seed_packet")
    post "/plants/#{plant.id}/advance", stage: "sown_indoor"
    assert_equal 302, last_response.status
    assert_equal "sown_indoor", plant.reload.lifecycle_stage
  end

  def test_batch_advance
    p1 = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "germinating")
    p2 = Plant.create(variety_name: "Roma", crop_type: "tomato", lifecycle_stage: "germinating")
    post "/plants/batch_advance", plant_ids: [p1.id, p2.id].join(","), stage: "seedling"
    assert_equal 302, last_response.status
    assert_equal "seedling", p1.reload.lifecycle_stage
    assert_equal "seedling", p2.reload.lifecycle_stage
  end

  def test_create_plant_json
    post "/api/plants", { variety_name: "Test", crop_type: "tomato" }.to_json,
         "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status
    assert_equal 1, Plant.count
  end
end
