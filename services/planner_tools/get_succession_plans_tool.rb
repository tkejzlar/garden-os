require "ruby_llm"
require_relative "../../models/succession_plan"
require_relative "../../models/task"

class GetSuccessionPlansTool < RubyLLM::Tool
  description "Get existing succession planting schedules with their completion status"

  def execute
    plans = SuccessionPlan.all.map do |sp|
      completed = Task.where(task_type: "sow")
                      .where(Sequel.like(:title, "%#{sp.crop}%"))
                      .where(status: "done").count
      {
        crop: sp.crop,
        varieties: sp.varieties_list,
        interval_days: sp.interval_days,
        season_start: sp.season_start&.to_s,
        season_end: sp.season_end&.to_s,
        total_planned: sp.total_planned_sowings,
        completed: completed,
        target_beds: sp.target_beds_list
      }
    end
    JSON.generate({ succession_plans: plans })
  end
end
