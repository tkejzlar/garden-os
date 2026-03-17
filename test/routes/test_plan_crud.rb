# test/routes/test_plan_crud.rb
require_relative "../test_helper"
require_relative "../../app"

class TestPlanCrud < GardenTest
  def test_create_plan
    post "/succession/plans", {
      crop: "Lettuce", varieties: "Tre Colori, Qualitas",
      interval_days: "18", season_start: "2026-04-01",
      season_end: "2026-09-30", target_beds: "BB1, BB2",
      total_planned_sowings: "8"
    }
    assert_equal 302, last_response.status
    assert_equal 1, SuccessionPlan.count
    plan = SuccessionPlan.first
    assert_equal "Lettuce", plan.crop
    assert_equal 18, plan.interval_days
    assert_equal ["Tre Colori", "Qualitas"], plan.varieties_list
  end

  def test_update_plan
    plan = SuccessionPlan.create(crop: "Lettuce", varieties: '["Tre Colori"]',
                                 interval_days: 18, total_planned_sowings: 8,
                                 garden_id: @garden.id)
    patch "/succession/plans/#{plan.id}", { interval_days: "21" }
    assert_equal 302, last_response.status
    assert_equal 21, plan.reload.interval_days
  end

  def test_delete_plan
    plan = SuccessionPlan.create(crop: "Lettuce", varieties: '["Tre Colori"]',
                                 interval_days: 18, total_planned_sowings: 8,
                                 garden_id: @garden.id)
    delete "/succession/plans/#{plan.id}"
    assert_equal 302, last_response.status
    assert_equal 0, SuccessionPlan.count
  end

  def test_generate_tasks_for_plan
    plan = SuccessionPlan.create(
      crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 18, season_start: Date.today,
      season_end: Date.today + 90, target_beds: '["BB1"]',
      total_planned_sowings: 4,
      garden_id: @garden.id
    )
    post "/succession/plans/#{plan.id}/generate"
    assert_equal 302, last_response.status
    # Should have generated at least 1 sowing task within the 14-day window
    tasks = Task.where(task_type: "sow").where(Sequel.like(:title, "%Lettuce%")).all
    refute_empty tasks
  end

  def test_create_manual_task
    post "/succession/tasks", {
      title: "Prepare bed BB1", task_type: "prep",
      due_date: Date.today.to_s, priority: "should"
    }
    assert_equal 302, last_response.status
    assert_equal 1, Task.count
    assert_equal "Prepare bed BB1", Task.first.title
  end

  def test_get_plan_form
    get "/succession/plans/new"
    assert_equal 200, last_response.status
  end

  def test_get_edit_plan_form
    plan = SuccessionPlan.create(crop: "Lettuce", varieties: '["Tre Colori"]',
                                 interval_days: 18, total_planned_sowings: 8,
                                 garden_id: @garden.id)
    get "/succession/plans/#{plan.id}/edit"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Lettuce"
  end
end
