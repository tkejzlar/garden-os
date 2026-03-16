require "ruby_llm"

class DraftPlanTool < RubyLLM::Tool
  description "Create a draft garden plan. The user will see a visual preview and can request changes before committing. Call this when you have a plan ready."

  param :payload, type: :string, desc: 'JSON string: { "summary": "overview text", "assignments": [{"bed_name": "BB1", "variety_name": "Raf", "crop_type": "tomato", "source": "Reinsaat"}], "successions": [{"crop": "Lettuce", "varieties": ["Tre Colori"], "interval_days": 18, "season_start": "2026-04-01", "season_end": "2026-09-30", "total_sowings": 8, "target_beds": ["SB1"]}], "tasks": [{"title": "Sow peppers indoors", "task_type": "sow", "due_date": "2026-03-01", "priority": "must", "notes": "...", "related_beds": ["Corner"]}] }. Assignments only need bed_name + variety_name + crop_type. Rows/slots are auto-created.'

  def execute(payload:)
    parsed = JSON.parse(payload)
    Thread.current[:planner_draft] = parsed

    a = parsed["assignments"]&.length || 0
    s = parsed["successions"]&.length || 0
    t = parsed["tasks"]&.length || 0
    "Draft stored: #{a} plant assignments, #{s} succession schedules, #{t} tasks. Present a summary to the user — they'll see a visual card with a 'Create this plan' button."
  rescue JSON::ParserError => e
    "Error: Invalid JSON. #{e.message}"
  end
end
