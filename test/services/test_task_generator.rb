require_relative "../test_helper"
require_relative "../../services/task_generator"

class TestTaskGenerator < GardenTest
  def test_generates_succession_sowing_task
    sp = SuccessionPlan.create(
      crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 18, season_start: Date.today - 20,
      season_end: Date.today + 90, target_beds: '["BB1"]',
      total_planned_sowings: 8
    )

    TaskGenerator.generate_succession_tasks!
    tasks = Task.where(task_type: "sow").all
    refute_empty tasks
    assert_includes tasks.first.title, "Lettuce"
  end

  def test_generates_germination_check_tasks
    Plant.create(variety_name: "Raf", crop_type: "tomato",
                 lifecycle_stage: "germinating", sow_date: Date.today - 7)
    StageHistory.create(plant_id: Plant.first.id, to_stage: "germinating",
                        changed_at: Time.now - (7 * 86400))

    TaskGenerator.generate_germination_checks!
    tasks = Task.where(task_type: "check").all
    refute_empty tasks
  end

  def test_no_duplicate_tasks
    Task.create(title: "Sow Lettuce #2", task_type: "sow",
                due_date: Date.today + 3, status: "upcoming")
    sp = SuccessionPlan.create(
      crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 18, season_start: Date.today - 20,
      season_end: Date.today + 90, target_beds: '["BB1"]',
      total_planned_sowings: 8
    )

    TaskGenerator.generate_succession_tasks!
    assert_equal 1, Task.where(task_type: "sow").where(Sequel.like(:title, "%Lettuce%")).count
  end
end
