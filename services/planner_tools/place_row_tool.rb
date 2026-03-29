require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceRowTool < RubyLLM::Tool
  description "Place plants in a horizontal row across a bed. Great for row-sowing patterns like lettuce rows or onion borders."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type (e.g., lettuce, tomato)"
  param :row_y, type: :string, desc: "Grid row position (0 = top/front of bed)"
  param :count, type: :string, desc: "Number of plants to place"
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, row_y:, count:, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    gw, gh = Plant.default_grid_size(crop_type)
    step = spacing ? spacing.to_i : gw
    n = count.to_i
    y = row_y.to_i

    created = 0
    n.times do |i|
      x = i * step
      break if x + gw > bed.grid_cols
      next unless bed.point_in_polygon?(x, y)

      Plant.create(
        garden_id: garden_id, bed_id: bed.id,
        variety_name: variety_name, crop_type: crop_type, source: source,
        lifecycle_stage: "seed_packet",
        grid_x: x, grid_y: y, grid_w: gw, grid_h: gh, quantity: 1
      )
      created += 1
    end

    Thread.current[:planner_needs_refresh] = true
    "Placed #{created} #{variety_name} in a row at y=#{y} on #{bed_name}."
  end
end
