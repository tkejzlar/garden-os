require_relative "../test_helper"
require_relative "../../app"

class TestSuccession < GardenTest
  def test_succession_index
    get "/succession"
    assert_equal 200, last_response.status
  end

  def test_succession_page_includes_alpine_component
    SuccessionPlan.create(crop: "Lettuce", varieties: '["Tre Colori"]',
                          interval_days: 18, total_planned_sowings: 8,
                          garden_id: @garden.id)
    get "/succession"
    assert_includes last_response.body, "x-data=\"gantt()\""
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
end
