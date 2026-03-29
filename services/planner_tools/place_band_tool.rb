require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceBandTool < RubyLLM::Tool
  description "Place a wide band/strip of dense planting — like a seed row or salad mix block. Creates one plant record with a large rectangular footprint and high quantity. Good for broadcast-sown crops (radish, mesclun, carrot)."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :orientation, type: :string, desc: '"horizontal" or "vertical"'
  param :position, type: :string, desc: "Grid row (horizontal) or column (vertical) to start the band"
  param :thickness, type: :string, desc: "Band width in grid cells (optional, uses crop default height)"
  param :length, type: :string, desc: "Band length in cells (optional, defaults to full bed width/height)"
  param :quantity, type: :string, desc: "Number of plants this band represents (optional, default 1)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, orientation:, position:, thickness: nil, length: nil, quantity: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    gw, gh = Plant.default_grid_size(crop_type)
    pos = position.to_i

    case orientation
    when "horizontal"
      band_w = length ? length.to_i : bed.grid_cols
      band_h = thickness ? thickness.to_i : gh
      x = 0
      y = pos
    when "vertical"
      band_w = thickness ? thickness.to_i : gw
      band_h = length ? length.to_i : bed.grid_rows
      x = pos
      y = 0
    else
      return "Error: orientation must be 'horizontal' or 'vertical'"
    end

    plant = Plant.create(
      garden_id: garden_id, bed_id: bed.id,
      variety_name: variety_name, crop_type: crop_type, source: source,
      lifecycle_stage: "seed_packet",
      grid_x: x, grid_y: y,
      grid_w: band_w.clamp(1, bed.grid_cols),
      grid_h: band_h.clamp(1, bed.grid_rows),
      quantity: quantity ? quantity.to_i : 1
    )

    Thread.current[:planner_needs_refresh] = true
    "Placed #{orientation} band of #{variety_name} at position #{pos}, size #{plant.grid_w}x#{plant.grid_h}, quantity #{plant.quantity}."
  end
end
