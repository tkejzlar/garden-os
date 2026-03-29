require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class GroupEditTool < RubyLLM::Tool
  description "Move or resize multiple plants at once. Filter by variety or crop type. Move shifts all matching plants by dx/dy grid cells. Resize sets new grid_w/grid_h."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :action, type: :string, desc: '"move" or "resize"'
  param :filter_variety, type: :string, desc: "Only affect this variety (optional)"
  param :filter_crop_type, type: :string, desc: "Only affect this crop type (optional)"
  param :dx, type: :string, desc: "Horizontal shift in grid cells (move only)"
  param :dy, type: :string, desc: "Vertical shift in grid cells (move only)"
  param :grid_w, type: :string, desc: "New width in grid cells (resize only)"
  param :grid_h, type: :string, desc: "New height in grid cells (resize only)"

  def execute(bed_name:, action:, filter_variety: nil, filter_crop_type: nil, dx: nil, dy: nil, grid_w: nil, grid_h: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    scope = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done")
    scope = scope.where(variety_name: filter_variety) if filter_variety
    scope = scope.where(crop_type: filter_crop_type) if filter_crop_type
    plants = scope.all
    return "No matching plants on #{bed_name}" if plants.empty?

    case action
    when "move"
      shift_x = dx ? dx.to_i : 0
      shift_y = dy ? dy.to_i : 0
      return "Error: provide dx and/or dy for move" if shift_x == 0 && shift_y == 0
      plants.each do |p|
        new_x = (p.grid_x + shift_x).clamp(0, bed.grid_cols - p.grid_w)
        new_y = (p.grid_y + shift_y).clamp(0, bed.grid_rows - p.grid_h)
        p.update(grid_x: new_x, grid_y: new_y, updated_at: Time.now)
      end
    when "resize"
      updates = {}
      updates[:grid_w] = grid_w.to_i if grid_w
      updates[:grid_h] = grid_h.to_i if grid_h
      return "Error: provide grid_w and/or grid_h for resize" if updates.empty?
      updates[:updated_at] = Time.now
      plants.each { |p| p.update(updates) }
    else
      return "Error: action must be 'move' or 'resize'"
    end

    Thread.current[:planner_needs_refresh] = true
    "#{action}: updated #{plants.length} plants on #{bed_name}."
  end
end
