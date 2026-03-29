require "ruby_llm"
require_relative "../../models/succession_plan"
require_relative "../../models/task"

class DeleteSuccessionPlanTool < RubyLLM::Tool
  description "Delete succession plan(s) for a crop and their pending (not yet completed) sow tasks. Completed tasks are preserved."

  param :crop, type: :string, desc: "Crop name to delete plans for (e.g., 'Lettuce')"
  param :target_bed, type: :string, desc: "Optional: only delete plans targeting this bed"

  def execute(crop:, target_bed: nil)
    garden_id = Thread.current[:current_garden_id]
    plans = SuccessionPlan.where(garden_id: garden_id, crop: crop).all

    if target_bed
      plans = plans.select { |p| p.target_beds_list.include?(target_bed) }
    end

    return "No succession plans found for '#{crop}'" if plans.empty?

    plan_count = plans.length
    task_count = 0

    DB.transaction do
      pending_tasks = Task.where(garden_id: garden_id, task_type: "sow")
        .where(Sequel.like(:title, "%#{crop}%"))
        .exclude(status: "done").all
      task_count = pending_tasks.length
      pending_tasks.each(&:destroy)

      plans.each(&:destroy)
    end

    Thread.current[:planner_needs_refresh] = true
    "Deleted #{plan_count} succession plan(s) for #{crop} and #{task_count} pending sow tasks."
  end
end
