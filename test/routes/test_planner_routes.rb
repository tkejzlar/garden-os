# test/routes/test_planner_routes.rb
require_relative "../test_helper"
require_relative "../../app"
require_relative "../../models/planner_message"

class TestPlannerRoutes < GardenTest
  def test_planner_message_requires_content
    post "/succession/planner/message", {}.to_json, "CONTENT_TYPE" => "application/json"
    assert_equal 400, last_response.status
  end

  def test_delete_messages
    PlannerMessage.create(role: "user", content: "test", created_at: Time.now, garden_id: @garden.id)
    delete "/succession/planner/messages"
    assert_equal 200, last_response.status
    assert_equal 0, PlannerMessage.count
  end

  def test_commit_validates_draft
    post "/succession/planner/commit",
      { draft_payload: { "assignments" => [{ "bed_name" => "FAKE" }], "successions" => [], "tasks" => [] } }.to_json,
      "CONTENT_TYPE" => "application/json"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    refute data["success"]
    assert_includes data["errors"].first, "FAKE"
  end

  def test_commit_creates_records
    bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id)
    row = Row.create(bed_id: bed.id, name: "A", position: 1)
    Slot.create(row_id: row.id, name: "Pos1", position: 1)

    draft = {
      "assignments" => [
        { "bed_name" => "BB1", "row_name" => "A", "slot_position" => 1,
          "variety_name" => "Raf", "crop_type" => "tomato" }
      ],
      "successions" => [],
      "tasks" => []
    }
    post "/succession/planner/commit",
      { draft_payload: draft }.to_json,
      "CONTENT_TYPE" => "application/json"

    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert data["success"]
    assert_equal 1, Plant.count
  end
end
