require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceSingleTool < RubyLLM::Tool
  description "Place a single plant at an exact grid position on a bed. Use for precise specimen placement or anchoring corners."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :grid_x, type: :string, desc: "Grid column position"
  param :grid_y, type: :string, desc: "Grid row position"
  param :grid_w, type: :string, desc: "Width in grid cells (optional, uses crop default)"
  param :grid_h, type: :string, desc: "Height in grid cells (optional, uses crop default)"
  param :quantity, type: :string, desc: "Number of plants in this cell (optional, default 1)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, grid_x:, grid_y:, grid_w: nil, grid_h: nil, quantity: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    dw, dh = Plant.default_grid_size(crop_type)

    plant = Plant.create(
      garden_id: garden_id, bed_id: bed.id,
      variety_name: variety_name, crop_type: crop_type, source: source,
      lifecycle_stage: "seed_packet",
      grid_x: grid_x.to_i, grid_y: grid_y.to_i,
      grid_w: grid_w ? grid_w.to_i : dw,
      grid_h: grid_h ? grid_h.to_i : dh,
      quantity: quantity ? quantity.to_i : 1
    )

    Thread.current[:planner_needs_refresh] = true
    "Placed #{variety_name} at (#{plant.grid_x}, #{plant.grid_y}) on #{bed_name}, size #{plant.grid_w}x#{plant.grid_h}."
  end
end
