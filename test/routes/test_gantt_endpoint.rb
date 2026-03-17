require_relative "../test_helper"
require_relative "../../app"

class TestGanttEndpoint < GardenTest
  def setup
    super
    @plan = SuccessionPlan.create(
      crop: "Spinach", varieties: '["Matador"]',
      interval_days: 14, total_planned_sowings: 3,
      season_start: Date.today, season_end: Date.today + 42,
      target_beds: '["BB3"]',
      garden_id: @garden.id
    )
  end

  def test_returns_200_with_json
    get "/api/succession/gantt"
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert body.key?("today")
    assert body.key?("plans")
  end

  def test_today_field_is_current_date
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    assert_equal Date.today.to_s, body["today"]
  end

  def test_plan_shape
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    plan = body["plans"].first
    assert_equal "Spinach", plan["crop"]
    assert_equal ["Matador"], plan["varieties"]
    assert_equal ["BB3"], plan["target_beds"]
    assert_equal 14, plan["interval_days"]
    assert plan.key?("bars")
  end

  def test_bar_color_done_is_green
    task = Task.create(title: "Sow Spinach #1", task_type: "sow",
                       due_date: Date.today - 7, status: "done", garden_id: @garden.id)
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    bar = body["plans"].first["bars"].first
    assert_equal "green", bar["color"]
    assert_equal "done", bar["status"]
  end

  def test_bar_color_upcoming_within_7_days_is_amber
    Task.create(title: "Sow Spinach #1", task_type: "sow",
                due_date: Date.today + 3, status: "upcoming", garden_id: @garden.id)
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    bar = body["plans"].first["bars"].first
    assert_equal "amber", bar["color"]
  end

  def test_bar_color_future_is_gray
    Task.create(title: "Sow Spinach #1", task_type: "sow",
                due_date: Date.today + 20, status: "upcoming", garden_id: @garden.id)
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    bar = body["plans"].first["bars"].first
    assert_equal "gray", bar["color"]
  end

  def test_bar_label_is_indexed
    Task.create(title: "Sow Spinach #1", task_type: "sow",
                due_date: Date.today + 14, status: "upcoming", garden_id: @garden.id)
    Task.create(title: "Sow Spinach #2", task_type: "sow",
                due_date: Date.today + 28, status: "upcoming", garden_id: @garden.id)
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    bars = body["plans"].first["bars"]
    assert_equal "Sow #1", bars[0]["label"]
    assert_equal "Sow #2", bars[1]["label"]
  end

  def test_empty_plans_returns_empty_array
    SuccessionPlan.dataset.delete
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    assert_equal [], body["plans"]
  end
end
