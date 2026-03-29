require "ruby_llm"
require_relative "../../models/succession_plan"

class UpdateSuccessionPlanTool < RubyLLM::Tool
  description "Update an existing succession plan's fields — interval, dates, target beds, varieties, or total sowings. Use to fix or adjust plans without deleting and recreating."

  param :crop, type: :string, desc: "Crop name to find the plan (e.g., 'Lettuce')"
  param :interval_days, type: :string, desc: "New interval between sowings (optional)"
  param :season_start, type: :string, desc: "New season start date YYYY-MM-DD (optional)"
  param :season_end, type: :string, desc: "New season end date YYYY-MM-DD (optional)"
  param :varieties, type: :string, desc: "New varieties JSON array (optional)"
  param :target_beds, type: :string, desc: "New target beds JSON array (optional)"
  param :total_sowings, type: :string, desc: "New total planned sowings (optional)"

  def execute(crop:, interval_days: nil, season_start: nil, season_end: nil, varieties: nil, target_beds: nil, total_sowings: nil)
    garden_id = Thread.current[:current_garden_id]
    plan = SuccessionPlan.where(garden_id: garden_id, crop: crop).first
    return "No succession plan found for '#{crop}'" unless plan

    updates = {}
    updates[:interval_days] = interval_days.to_i if interval_days
    updates[:season_start] = Date.parse(season_start) if season_start
    updates[:season_end] = Date.parse(season_end) if season_end
    updates[:varieties] = (JSON.parse(varieties)).to_json if varieties
    updates[:target_beds] = (JSON.parse(target_beds)).to_json if target_beds
    updates[:total_planned_sowings] = total_sowings.to_i if total_sowings

    return "Error: nothing to update" if updates.empty?

    plan.update(updates)
    Thread.current[:planner_needs_refresh] = true
    "Updated succession plan for #{crop}: #{updates.map { |k, v| "#{k}=#{v}" }.join(', ')}"
  end
end
