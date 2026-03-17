require_relative "../test_helper"
require_relative "../../services/plan_committer"

class TestPlanCommitter < GardenTest
  def setup
    super
    # Create a bed with grid dimensions for testing
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
  end

  def test_commit_assignments
    draft = {
      "assignments" => [
        { "bed_name" => "BB1",
          "variety_name" => "Raf", "crop_type" => "tomato", "source" => "Reinsaat" }
      ],
      "successions" => [],
      "tasks" => []
    }
    result = PlanCommitter.commit!(draft, garden_id: @garden.id)
    assert result[:success]
    assert_equal 1, result[:created][:plants]
    assert_equal "Raf", Plant.first.variety_name
    assert_equal @bed.id, Plant.first.bed_id
  end

  def test_commit_successions
    draft = {
      "assignments" => [],
      "successions" => [
        { "crop" => "Lettuce", "varieties" => ["Tre Colori"], "interval_days" => 18,
          "season_start" => "2026-04-01", "season_end" => "2026-09-30",
          "total_sowings" => 4, "target_beds" => ["BB1"] }
      ],
      "tasks" => []
    }
    result = PlanCommitter.commit!(draft, garden_id: @garden.id)
    assert result[:success]
    assert_equal 1, result[:created][:succession_plans]
    assert_equal "Lettuce", SuccessionPlan.first.crop
  end

  def test_commit_tasks
    draft = {
      "assignments" => [],
      "successions" => [],
      "tasks" => [
        { "title" => "Sow peppers", "task_type" => "sow",
          "due_date" => "2026-03-01", "priority" => "must",
          "related_beds" => ["BB1"] }
      ]
    }
    result = PlanCommitter.commit!(draft, garden_id: @garden.id)
    assert result[:success]
    assert_equal 1, result[:created][:tasks]
    assert_equal "Sow peppers", Task.first.title
  end

  def test_validates_bed_names
    draft = {
      "assignments" => [
        { "bed_name" => "NONEXISTENT", "variety_name" => "Raf", "crop_type" => "tomato" }
      ],
      "successions" => [],
      "tasks" => []
    }
    result = PlanCommitter.commit!(draft, garden_id: @garden.id)
    refute result[:success]
    assert_includes result[:errors].first, "NONEXISTENT"
  end

  def test_empty_draft
    result = PlanCommitter.commit!({ "assignments" => [], "successions" => [], "tasks" => [] }, garden_id: @garden.id)
    assert result[:success]
    assert_equal 0, Plant.count
  end
end
