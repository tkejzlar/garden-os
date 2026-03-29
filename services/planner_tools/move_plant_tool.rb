require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class MovePlantTool < RubyLLM::Tool
  description "Move a plant from its current bed to a different bed. Auto-places it below existing plants on the target bed."

  param :plant_id, type: :string, desc: "ID of the plant to move"
  param :target_bed_name, type: :string, desc: "Name of the destination bed"

  def execute(plant_id:, target_bed_name:)
    garden_id = Thread.current[:current_garden_id]
    plant = Plant[plant_id.to_i]
    return "Error: plant not found" unless plant && plant.garden_id == garden_id

    bed = Bed.where(name: target_bed_name, garden_id: garden_id).first
    return "Error: bed '#{target_bed_name}' not found" unless bed

    existing = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    next_y = existing.any? ? existing.map { |p| (p.grid_y || 0) + (p.grid_h || 1) }.max : 0

    plant.update(
      bed_id: bed.id,
      grid_x: 0,
      grid_y: next_y.clamp(0, bed.grid_rows - 1),
      updated_at: Time.now
    )

    Thread.current[:planner_needs_refresh] = true
    "Moved #{plant.variety_name} (#{plant.crop_type}) to #{target_bed_name} at row #{next_y}."
  end
end
