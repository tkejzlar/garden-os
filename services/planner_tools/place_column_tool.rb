require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceColumnTool < RubyLLM::Tool
  description "Place plants in a vertical column down a bed. Great for tall crops along the back or trellised plants."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :col_x, type: :string, desc: "Grid column position: number, or 'left', 'right', 'middle'"
  param :count, type: :string, desc: "Number of plants"
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, col_x:, count:, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    gw, gh = Plant.default_grid_size(crop_type)
    step = spacing ? spacing.to_i : gh
    n = count.to_i
    x = bed.resolve_col(col_x)

    created = 0
    n.times do |i|
      y = i * step
      break if y + gh > bed.grid_rows
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
    "Placed #{created} #{variety_name} in a column at x=#{x} on #{bed_name}."
  end
end
