require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/plant"
require_relative "../../models/succession_plan"
require_relative "../../services/planner_tools/update_succession_plan_tool"
require_relative "../../services/planner_tools/deduplicate_succession_plans_tool"

class TestUpdateSuccessionPlanTool < GardenTest
  def setup
    super
    @plan = SuccessionPlan.create(
      garden_id: @garden.id, crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 14, season_start: Date.new(2026, 4, 1), season_end: Date.new(2026, 9, 30),
      total_planned_sowings: 5, target_beds: '["BB1"]'
    )
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_updates_interval
    tool = UpdateSuccessionPlanTool.new
    tool.execute(crop: "Lettuce", interval_days: "21")
    @plan.refresh
    assert_equal 21, @plan.interval_days
  end

  def test_updates_target_beds
    tool = UpdateSuccessionPlanTool.new
    tool.execute(crop: "Lettuce", target_beds: '["BB1", "SB1"]')
    @plan.refresh
    assert_equal ["BB1", "SB1"], @plan.target_beds_list
  end

  def test_not_found
    tool = UpdateSuccessionPlanTool.new
    result = tool.execute(crop: "Mango", interval_days: "10")
    assert_includes result, "No succession plan found"
  end
end

class TestDeduplicateSuccessionPlansTool < GardenTest
  def setup
    super
    SuccessionPlan.create(garden_id: @garden.id, crop: "Lettuce", varieties: '["Tre Colori"]', interval_days: 14, season_start: Date.new(2026, 4, 1), season_end: Date.new(2026, 9, 30), total_planned_sowings: 5, target_beds: '["BB1"]')
    SuccessionPlan.create(garden_id: @garden.id, crop: "lettuce", varieties: '["Salanova"]', interval_days: 14, season_start: Date.new(2026, 4, 1), season_end: Date.new(2026, 9, 30), total_planned_sowings: 3, target_beds: '["SB1"]')
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_merges_duplicates
    tool = DeduplicateSuccessionPlansTool.new
    result = tool.execute(crop: "Lettuce")
    assert_includes result, "1"
    plans = SuccessionPlan.where(garden_id: @garden.id).all
    assert_equal 1, plans.length
    assert_includes plans.first.varieties_list, "Tre Colori"
    assert_includes plans.first.varieties_list, "Salanova"
    assert_includes plans.first.target_beds_list, "BB1"
    assert_includes plans.first.target_beds_list, "SB1"
  end

  def test_no_duplicates
    SuccessionPlan.where(garden_id: @garden.id).all[1..].each(&:destroy)
    tool = DeduplicateSuccessionPlansTool.new
    result = tool.execute(crop: "Lettuce")
    assert_includes result, "No duplicate"
  end
end
