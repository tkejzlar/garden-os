require "ruby_llm"

class DraftBedLayoutTool < RubyLLM::Tool
  description "Suggest a plant layout for a specific garden bed. Use when the user asks about what to plant in a bed, how to arrange plants, or wants a layout plan. Returns structured data that the user can preview and apply."

  param :payload, type: :string, desc: 'JSON string: { "bed_name": "BB1", "action": "fill|rearrange|plan_full", "suggestions": [{"slot_id": 42, "variety_name": "Raf", "crop_type": "tomato", "reason": "Companion to basil"}], "moves": [{"plant_id": 12, "from_slot_id": 42, "to_slot_id": 45, "reason": "Move basil next to tomatoes"}] }. Use "suggestions" for fill/plan_full, "moves" for rearrange.'

  def execute(payload:)
    parsed = JSON.parse(payload)
    Thread.current[:planner_bed_layout] = parsed

    action = parsed["action"]
    case action
    when "fill"
      count = parsed["suggestions"]&.length || 0
      "Bed layout draft stored: #{count} planting suggestions for #{parsed['bed_name']}. Present the suggestions to the user — they'll see a visual preview on the bed with an 'Apply layout' button."
    when "rearrange"
      count = parsed["moves"]&.length || 0
      "Bed layout draft stored: #{count} move suggestions for #{parsed['bed_name']}. Present the suggestions to the user — they'll see the proposed moves on the bed."
    when "plan_full"
      count = parsed["suggestions"]&.length || 0
      "Bed layout draft stored: full plan with #{count} plants for #{parsed['bed_name']}. Present the plan to the user — they'll see all suggested plants on the bed."
    else
      "Bed layout draft stored for #{parsed['bed_name']}."
    end
  rescue JSON::ParserError => e
    "Error: Invalid JSON. #{e.message}"
  end
end
