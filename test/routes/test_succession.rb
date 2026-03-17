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
    bed = Bed.create(garden_id: @garden.id, name: "BB1")
    row = Row.create(bed_id: bed.id, name: "R1", position: 1)
    slot = Slot.create(row_id: row.id, name: "S1", position: 1)

    plant = Plant.create(
      garden_id: @garden.id,
      slot_id: slot.id,
      variety_name: "Raf",
      crop_type: "tomato",
      lifecycle_stage: "planted_out",
      sow_date: Date.today - 30
    )

    get "/api/plan/bed-timeline"
    assert_equal 200, last_response.status

    data = JSON.parse(last_response.body)
    assert_equal Date.today.to_s, data["today"]
    assert data["beds"].is_a?(Array)
    assert_equal 1, data["beds"].length

    bed_data = data["beds"].first
    assert_equal "BB1", bed_data["bed_name"]
    assert_equal 1, bed_data["total_slots"]
    assert bed_data["occupancy"].is_a?(Array)
    assert bed_data["crops"].is_a?(Array)
    assert_equal "tomato", bed_data["crops"].first["crop"]
  end

  def test_swap_slots
    bed = Bed.create(garden_id: @garden.id, name: "SwapBed")
    row = Row.create(bed_id: bed.id, position: 1, name: "R1")
    slot_a = Slot.create(row_id: row.id, position: 1, name: "A1")
    slot_b = Slot.create(row_id: row.id, position: 2, name: "B1")

    plant_a = Plant.create(garden_id: @garden.id, slot_id: slot_a.id, variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seedling")
    plant_b = Plant.create(garden_id: @garden.id, slot_id: slot_b.id, variety_name: "Basil", crop_type: "herb", lifecycle_stage: "seedling")

    patch "/beds/#{bed.id}/swap-slots", { slot_a: slot_a.id, slot_b: slot_b.id }.to_json, { "CONTENT_TYPE" => "application/json" }
    assert_equal 200, last_response.status

    plant_a.refresh
    plant_b.refresh
    assert_equal slot_b.id, plant_a.slot_id
    assert_equal slot_a.id, plant_b.slot_id
  end

  def test_apply_layout_fill
    bed = Bed.create(garden_id: @garden.id, name: "FillBed")
    row = Row.create(bed_id: bed.id, position: 1, name: "R1")
    slot = Slot.create(row_id: row.id, position: 1, name: "S1")

    post "/beds/#{bed.id}/apply-layout", {
      action: "fill",
      suggestions: [
        { slot_id: slot.id, variety_name: "Cherry Belle", crop_type: "radish" }
      ]
    }.to_json, { "CONTENT_TYPE" => "application/json" }

    assert_equal 200, last_response.status

    plant = Plant.where(slot_id: slot.id).first
    assert plant
    assert_equal "Cherry Belle", plant.variety_name
    assert_equal "radish", plant.crop_type
    assert_equal "seed_packet", plant.lifecycle_stage
  end
end
