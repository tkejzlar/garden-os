require_relative "../test_helper"
require_relative "../../app"

class TestSuccession < GardenTest
  def test_succession_index
    get "/succession"
    assert_equal 200, last_response.status
  end

  def test_succession_page_includes_alpine_component
    SuccessionPlan.create(
      crop: "Lettuce",
      varieties: '["Tre Colori"]',
      interval_days: 14,
      total_planned_sowings: 5,
      garden_id: @garden.id
    )

    get "/succession"
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'x-data="planTab()"'
    assert_includes last_response.body, "Season Plan"
    assert_includes last_response.body, "Tasks"
    assert_includes last_response.body, "Timeline"
    assert_includes last_response.body, "Beds"
  end

  def test_succession_index_has_summary_strip
    # Create a task that's due this week
    Task.create(
      garden_id: @garden.id,
      title: "Sow lettuce",
      task_type: "sow",
      due_date: Date.today + 2,
      priority: "must",
      status: "upcoming"
    )
    # Create an overdue task
    Task.create(
      garden_id: @garden.id,
      title: "Transplant peppers",
      task_type: "transplant",
      due_date: Date.today - 3,
      priority: "should",
      status: "upcoming"
    )
    # Create a done task
    Task.create(
      garden_id: @garden.id,
      title: "Order seeds",
      task_type: "order",
      status: "done",
      completed_at: Time.now
    )

    get "/succession"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "This week"
    assert_includes last_response.body, "Overdue"
  end

  def test_succession_api_still_works
    SuccessionPlan.create(crop: "Lettuce", varieties: '["Tre Colori"]',
                          interval_days: 18, total_planned_sowings: 8,
                          season_start: Date.today, season_end: Date.today + 90,
                          target_beds: '["BB1"]',
                          garden_id: @garden.id)
    get "/api/succession"
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal "Lettuce", body.first["crop"]
  end

  def test_bed_timeline_api
    bed = Bed.create(garden_id: @garden.id, name: "BB1", width: 40, length: 30)

    plant = Plant.create(
      garden_id: @garden.id,
      bed_id: bed.id,
      variety_name: "Raf",
      crop_type: "tomato",
      lifecycle_stage: "planted_out",
      sow_date: Date.today - 30,
      grid_x: 0, grid_y: 0, grid_w: 1, grid_h: 1,
      quantity: 1
    )

    get "/api/plan/bed-timeline"
    assert_equal 200, last_response.status

    data = JSON.parse(last_response.body)
    assert_equal Date.today.to_s, data["today"]
    assert data["beds"].is_a?(Array)
    assert_equal 1, data["beds"].length

    bed_data = data["beds"].first
    assert_equal "BB1", bed_data["bed_name"]
    assert bed_data.key?("grid_cols")
    assert bed_data.key?("grid_rows")
    assert bed_data["occupancy"].is_a?(Array)
    assert bed_data["crops"].is_a?(Array)
    assert_equal "tomato", bed_data["crops"].first["crop"]
  end

  def test_swap_plants
    bed = Bed.create(garden_id: @garden.id, name: "SwapBed", width: 40, length: 30)

    plant_a = Plant.create(garden_id: @garden.id, bed_id: bed.id, variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seedling", grid_x: 0, grid_y: 0, grid_w: 1, grid_h: 1, quantity: 1)
    plant_b = Plant.create(garden_id: @garden.id, bed_id: bed.id, variety_name: "Basil", crop_type: "herb", lifecycle_stage: "seedling", grid_x: 2, grid_y: 1, grid_w: 1, grid_h: 1, quantity: 1)

    patch "/beds/#{bed.id}/swap-plants", { plant_a: plant_a.id, plant_b: plant_b.id }.to_json, { "CONTENT_TYPE" => "application/json" }
    assert_equal 200, last_response.status

    plant_a.refresh
    plant_b.refresh
    assert_equal 2, plant_a.grid_x
    assert_equal 1, plant_a.grid_y
    assert_equal 0, plant_b.grid_x
    assert_equal 0, plant_b.grid_y
  end

  def test_apply_layout_fill
    bed = Bed.create(garden_id: @garden.id, name: "FillBed", width: 40, length: 30)

    post "/beds/#{bed.id}/apply-layout", {
      action: "fill",
      suggestions: [
        { variety_name: "Cherry Belle", crop_type: "radish", grid_x: 1, grid_y: 2, grid_w: 1, grid_h: 1, quantity: 1 }
      ]
    }.to_json, { "CONTENT_TYPE" => "application/json" }

    assert_equal 200, last_response.status

    plant = Plant.where(bed_id: bed.id, variety_name: "Cherry Belle").first
    assert plant
    assert_equal "Cherry Belle", plant.variety_name
    assert_equal "radish", plant.crop_type
    assert_equal "seed_packet", plant.lifecycle_stage
    assert_equal 1, plant.grid_x
    assert_equal 2, plant.grid_y
  end
end
