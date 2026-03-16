# test/routes/test_garden.rb
require_relative "../test_helper"
require_relative "../../app"

class TestGarden < GardenTest

  # ── GET /garden ──────────────────────────────────────────────────────────────

  def test_garden_page_renders
    Bed.create(name: "North Bed", bed_type: "raised")
    get "/garden"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "North Bed"
  end

  def test_garden_page_empty_state
    get "/garden"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "gardenDesigner"  # Alpine component present
  end

  # ── GET /beds redirects ──────────────────────────────────────────────────────

  def test_beds_redirects_to_garden
    get "/beds"
    assert_equal 301, last_response.status
    assert_equal "http://example.org/garden", last_response.headers["Location"]
  end

  # ── POST /api/beds ───────────────────────────────────────────────────────────

  def test_create_bed_minimal
    post "/api/beds",
         { name: "South Bed" }.to_json,
         "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal "South Bed", data["name"]
    assert_nil data["canvas_x"]
  end

  def test_create_bed_with_canvas_position
    post "/api/beds",
         { name: "East Bed", canvas_x: 100.0, canvas_y: 50.0,
           canvas_width: 200.0, canvas_height: 120.0 }.to_json,
         "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status
    data = JSON.parse(last_response.body)
    assert_in_delta 100.0, data["canvas_x"]
    assert_in_delta 50.0,  data["canvas_y"]
  end

  def test_create_bed_missing_name_returns_422
    post "/api/beds",
         { bed_type: "raised" }.to_json,
         "CONTENT_TYPE" => "application/json"
    assert_equal 422, last_response.status
  end

  def test_create_bed_invalid_json_returns_400
    post "/api/beds", "not json", "CONTENT_TYPE" => "application/json"
    assert_equal 400, last_response.status
  end

  # ── PATCH /api/beds/:id/position ─────────────────────────────────────────────

  def test_patch_position_updates_canvas_fields
    bed = Bed.create(name: "West Bed", bed_type: "raised")
    patch "/api/beds/#{bed.id}/position",
          { canvas_x: 30.0, canvas_y: 40.0,
            canvas_width: 150.0, canvas_height: 80.0 }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_in_delta 30.0,  data["canvas_x"]
    assert_in_delta 40.0,  data["canvas_y"]
    assert_in_delta 150.0, data["canvas_width"]
    assert_in_delta 80.0,  data["canvas_height"]
  end

  def test_patch_position_with_polygon_points
    bed = Bed.create(name: "Odd Bed", bed_type: "raised")
    pts = [[0, 0], [100, 0], [80, 60], [20, 60]]
    patch "/api/beds/#{bed.id}/position",
          { canvas_x: 0.0, canvas_y: 0.0, canvas_points: pts }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal pts, JSON.parse(data["canvas_points"])
  end

  def test_patch_position_unknown_bed_returns_404
    patch "/api/beds/99999/position",
          { canvas_x: 0.0 }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 404, last_response.status
  end

  # ── PATCH /api/beds/:id ──────────────────────────────────────────────────────

  def test_patch_bed_updates_name
    bed = Bed.create(name: "Old Name", bed_type: "raised")
    patch "/api/beds/#{bed.id}",
          { name: "New Name" }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 200, last_response.status
    assert_equal "New Name", JSON.parse(last_response.body)["name"]
  end

  def test_patch_bed_unknown_returns_404
    patch "/api/beds/99999",
          { name: "Ghost" }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 404, last_response.status
  end
end
