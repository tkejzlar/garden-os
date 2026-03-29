require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class ClearBedTool < RubyLLM::Tool
  description "Remove ALL plants from a bed. Use when the user wants to start a bed from scratch or redesign it completely. Confirm with the user before calling this."

  param :bed_name, type: :string, desc: "Exact bed name as returned by get_beds"

  def execute(bed_name:)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    count = plants.length
    plants.each(&:destroy)

    Thread.current[:planner_needs_refresh] = true
    "Cleared #{count} plants from #{bed_name}."
  end
end
