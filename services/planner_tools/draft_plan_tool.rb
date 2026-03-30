require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class DraftPlanTool < RubyLLM::Tool
  description "Create a draft garden plan. The user will see a visual preview and can request changes before committing. Call this when you have a plan ready."

  param :payload, type: :string, desc: 'JSON string: { "summary": "overview text", "assignments": [{"bed_name": "BB1", "variety_name": "Raf", "crop_type": "tomato", "source": "Reinsaat"}], "successions": [{"crop": "Lettuce", "varieties": ["Tre Colori"], "interval_days": 18, "season_start": "2026-04-01", "season_end": "2026-09-30", "total_sowings": 8, "target_beds": ["SB1"]}], "tasks": [{"title": "Sow peppers indoors", "task_type": "sow", "due_date": "2026-03-01", "priority": "must", "notes": "...", "related_beds": ["Corner"]}] }. Assignments only need bed_name + variety_name + crop_type. Plants are placed on the bed grid with grid_x/y/w/h coordinates. Include "mode": "replace" to clear target beds before applying, or "mode": "add" (default) to add on top of existing plants.'

  def execute(payload:)
    parsed = JSON.parse(payload)
    Thread.current[:planner_draft] = parsed

    a = parsed["assignments"]&.length || 0
    s = parsed["successions"]&.length || 0
    t = parsed["tasks"]&.length || 0

    # Check for duplicate assignments
    warnings = []
    garden_id = Thread.current[:current_garden_id]
    (parsed["assignments"] || []).each do |assignment|
      bed = Bed.where(name: assignment["bed_name"], garden_id: garden_id).first
      next unless bed
      existing = Plant.where(
        bed_id: bed.id,
        variety_name: assignment["variety_name"],
        crop_type: assignment["crop_type"]
      ).exclude(lifecycle_stage: "done").count
      if existing > 0
        warnings << "#{assignment['bed_name']} already has #{existing} #{assignment['variety_name']} (#{assignment['crop_type']})"
      end
    end

    msg = "Draft stored: #{a} plant assignments, #{s} succession schedules, #{t} tasks."
    msg += " WARNINGS: #{warnings.join('; ')}. Ask the user whether to replace or add." if warnings.any?
    msg += " Present a summary to the user — they'll see a visual card with a 'Create this plan' button."
    msg
  rescue JSON::ParserError => e
    "Error: Invalid JSON. #{e.message}"
  end
end
