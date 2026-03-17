require_relative "../test_helper"
require_relative "../../app"

class TestReschedule < GardenTest
  def test_reschedule_updates_due_date
    task = Task.create(title: "Sow lettuce #1", task_type: "sow",
                       due_date: Date.today, status: "upcoming", garden_id: @garden.id)
    patch "/tasks/#{task.id}/reschedule", due_date: (Date.today + 7).to_s
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal (Date.today + 7).to_s, body["due_date"]
    assert_equal (Date.today + 7), task.reload.due_date
  end

  def test_reschedule_404_for_missing_task
    patch "/tasks/99999/reschedule", due_date: Date.today.to_s
    assert_equal 404, last_response.status
  end

  def test_reschedule_422_without_date
    task = Task.create(title: "Sow lettuce #2", task_type: "sow",
                       due_date: Date.today, status: "upcoming", garden_id: @garden.id)
    patch "/tasks/#{task.id}/reschedule"
    assert_equal 422, last_response.status
  end

  def test_reschedule_422_with_invalid_date
    task = Task.create(title: "Sow lettuce #3", task_type: "sow",
                       due_date: Date.today, status: "upcoming", garden_id: @garden.id)
    patch "/tasks/#{task.id}/reschedule", due_date: "not-a-date"
    assert_equal 422, last_response.status
  end

  def test_reschedule_does_not_touch_succession_plan
    plan = SuccessionPlan.create(
      crop: "Basil", varieties: '["Genovese"]',
      interval_days: 14, total_planned_sowings: 4,
      season_start: Date.today, season_end: Date.today + 56,
      target_beds: '["BB2"]',
      garden_id: @garden.id
    )
    task = Task.create(title: "Sow Basil #1", task_type: "sow",
                       due_date: Date.today, status: "upcoming", garden_id: @garden.id)
    original_interval = plan.interval_days
    patch "/tasks/#{task.id}/reschedule", due_date: (Date.today + 3).to_s
    assert_equal 200, last_response.status
    assert_equal original_interval, plan.reload.interval_days
  end
end

class TestMarkDoneViaTaskRoute < GardenTest
  # The Gantt's "Mark done" button calls POST /tasks/:id/complete,
  # which is the existing task-complete route. Verify it still works.
  def test_mark_done_via_existing_complete_route
    task = Task.create(title: "Sow Tomato #1", task_type: "sow",
                       due_date: Date.today, status: "upcoming", garden_id: @garden.id)
    post "/tasks/#{task.id}/complete"
    # Route returns 302 redirect; task should be done
    assert_includes [200, 302], last_response.status
    assert_equal "done", task.reload.status
  end
end
