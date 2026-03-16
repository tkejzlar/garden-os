require "ruby_llm"

class DraftPlanTool < RubyLLM::Tool
  description "Create a draft garden plan with bed assignments, succession schedules, and tasks. The user will see a visual preview and can request changes before committing. Call this when you have a complete plan ready to present."

  param :payload, type: :string, desc: "JSON string containing: summary (string), assignments (array of {bed_name, row_name, slot_position, variety_name, crop_type, source}), successions (array of {crop, varieties, interval_days, season_start, season_end, total_sowings, target_beds}), tasks (array of {title, task_type, due_date, priority, notes, related_beds})"

  def execute(payload:)
    parsed = JSON.parse(payload)
    Thread.current[:planner_draft] = parsed
    "Draft plan stored with #{parsed['assignments']&.length || 0} bed assignments, #{parsed['successions']&.length || 0} succession schedules, and #{parsed['tasks']&.length || 0} tasks. Present the summary to the user. They will see a visual preview and can click 'Create this plan' to commit it, or ask for changes."
  rescue JSON::ParserError => e
    "Error: Invalid JSON in payload. Please fix and try again: #{e.message}"
  end
end
