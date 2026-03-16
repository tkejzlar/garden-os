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

  # --- Harvest routes ---

  def test_log_harvest_creates_record
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    post "/plants/#{plant.id}/harvests", quantity: "large", date: "2026-03-16", notes: "First pick"
    assert_equal 302, last_response.status
    assert_equal 1, Harvest.where(plant_id: plant.id).count
    h = Harvest.where(plant_id: plant.id).first
    assert_equal "large",      h.quantity
    assert_equal "First pick", h.notes
    assert_equal Date.new(2026, 3, 16), h.date
  end

  def test_log_harvest_defaults_date_to_today
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    post "/plants/#{plant.id}/harvests", quantity: "small"
    assert_equal 302, last_response.status
    h = Harvest.where(plant_id: plant.id).first
    assert_equal Date.today, h.date
  end

  def test_log_harvest_invalid_quantity_returns_200
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    post "/plants/#{plant.id}/harvests", quantity: "enormous"
    assert_equal 200, last_response.status
    assert_equal 0, Harvest.where(plant_id: plant.id).count
  end

  def test_log_harvest_unknown_plant_returns_404
    post "/plants/99999/harvests", quantity: "small"
    assert_equal 404, last_response.status
  end

  def test_api_harvests_returns_json_array
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    Harvest.create(plant_id: plant.id, date: Date.today, quantity: "medium")
    Harvest.create(plant_id: plant.id, date: Date.today - 1, quantity: "small")
    get "/api/plants/#{plant.id}/harvests"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 2,        data.length
    assert_equal "medium", data.first["quantity"]   # ordered desc by date
    assert_equal "small",  data.last["quantity"]
  end

  def test_api_harvests_unknown_plant_returns_404
    get "/api/plants/99999/harvests"
    assert_equal 404, last_response.status
  end

  def test_plant_show_includes_harvest_section
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    Harvest.create(plant_id: plant.id, date: Date.today, quantity: "huge", notes: "Bumper crop")
    get "/plants/#{plant.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Log harvest"
    assert_includes last_response.body, "Bumper crop"
    assert_includes last_response.body, "huge"
  end
end
