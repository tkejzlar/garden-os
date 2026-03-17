require_relative "../test_helper"
require_relative "../../services/task_generator"

# Minimal stub helper for class methods (minitest 6 has no minitest/mock)
module ClassStub
  def stub(method_name, val_or_callable, &block)
    original = method(method_name)
    define_singleton_method(method_name) do |*a|
      val_or_callable.respond_to?(:call) ? val_or_callable.call(*a) : val_or_callable
    end
    block.call
  ensure
    define_singleton_method(method_name, original)
  end
end

SensorService.extend(ClassStub) unless SensorService.singleton_class.ancestors.include?(ClassStub)

class TestTaskGenerator < GardenTest
  def test_generates_succession_sowing_task
    sp = SuccessionPlan.create(
      crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 18, season_start: Date.today - 20,
      season_end: Date.today + 90, target_beds: '["BB1"]',
      total_planned_sowings: 8,
      garden_id: @garden.id
    )

    TaskGenerator.generate_succession_tasks!
    tasks = Task.where(task_type: "sow").all
    refute_empty tasks
    assert_includes tasks.first.title, "Lettuce"
  end

  def test_generates_germination_check_tasks
    Plant.create(variety_name: "Raf", crop_type: "tomato",
                 lifecycle_stage: "germinating", sow_date: Date.today - 7,
                 garden_id: @garden.id)
    StageHistory.create(plant_id: Plant.first.id, to_stage: "germinating",
                        changed_at: Time.now - (7 * 86400))

    TaskGenerator.generate_germination_checks!
    tasks = Task.where(task_type: "check").all
    refute_empty tasks
  end

  def test_no_duplicate_tasks
    Task.create(title: "Sow Lettuce #2", task_type: "sow",
                due_date: Date.today + 3, status: "upcoming", garden_id: @garden.id)
    sp = SuccessionPlan.create(
      crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 18, season_start: Date.today - 20,
      season_end: Date.today + 90, target_beds: '["BB1"]',
      total_planned_sowings: 8,
      garden_id: @garden.id
    )

    TaskGenerator.generate_succession_tasks!
    assert_equal 1, Task.where(task_type: "sow").where(Sequel.like(:title, "%Lettuce%")).count
  end

  # ---------------------------------------------------------------------------
  # auto_skip_watering_tasks!
  # ---------------------------------------------------------------------------

  def test_auto_skip_watering_tasks_skips_when_rain_detected
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Water tomatoes", task_type: "water",
                       due_date: Date.today, status: "upcoming", priority: "should",
                       garden_id: @garden.id)

    SensorService.stub(:rain_detected?, true) do
      SensorService.stub(:irrigation_active?, false) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "skipped", task.status
    assert_includes task.notes.to_s, "Auto-skipped: rain detected"
  end

  def test_auto_skip_watering_tasks_skips_when_irrigation_active
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Water herbs", task_type: "water",
                       due_date: Date.today, status: "upcoming", priority: "should",
                       garden_id: @garden.id)

    SensorService.stub(:rain_detected?, false) do
      SensorService.stub(:irrigation_active?, true) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "skipped", task.status
    assert_includes task.notes.to_s, "Auto-skipped: irrigation active"
  end

  def test_auto_skip_watering_tasks_does_not_skip_when_no_conditions
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Water seedlings", task_type: "water",
                       due_date: Date.today, status: "upcoming", priority: "should",
                       garden_id: @garden.id)

    SensorService.stub(:rain_detected?, false) do
      SensorService.stub(:irrigation_active?, false) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "upcoming", task.status
  end

  def test_auto_skip_watering_tasks_does_not_touch_done_tasks
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Water beds", task_type: "water",
                       due_date: Date.today, status: "done", priority: "should",
                       garden_id: @garden.id)

    SensorService.stub(:rain_detected?, true) do
      SensorService.stub(:irrigation_active?, false) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "done", task.status
  end

  def test_auto_skip_does_not_affect_non_water_tasks
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Sow Lettuce #1", task_type: "sow",
                       due_date: Date.today, status: "upcoming", priority: "should",
                       garden_id: @garden.id)

    SensorService.stub(:rain_detected?, true) do
      SensorService.stub(:irrigation_active?, false) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "upcoming", task.status
  end
end
