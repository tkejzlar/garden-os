require "ruby_llm"
require "json"
require "set"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceFillTool < RubyLLM::Tool
  description "Fill a bed (or region within a bed) with plants at proper spacing, skipping occupied cells. Use for dense planting of herbs, greens, or root crops."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :region, type: :string, desc: 'Optional JSON: {"from_x":0,"from_y":0,"to_x":10,"to_y":10}. Defaults to entire bed.'
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, region: nil, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    gw, gh = Plant.default_grid_size(crop_type)
    step_x = spacing ? spacing.to_i : gw
    step_y = spacing ? spacing.to_i : gh

    if region
      r = JSON.parse(region) rescue {}
      from_x = r["from_x"]&.to_i || 0
      from_y = r["from_y"]&.to_i || 0
      to_x = r["to_x"]&.to_i || bed.grid_cols
      to_y = r["to_y"]&.to_i || bed.grid_rows
    else
      from_x, from_y = 0, 0
      to_x, to_y = bed.grid_cols, bed.grid_rows
    end

    # Build occupied cell set
    existing = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    occupied = Set.new
    existing.each do |p|
      (p.grid_x...(p.grid_x + p.grid_w)).each do |cx|
        (p.grid_y...(p.grid_y + p.grid_h)).each do |cy|
          occupied.add([cx, cy])
        end
      end
    end

    created = 0
    y = from_y
    while y + gh <= to_y
      x = from_x
      while x + gw <= to_x
        overlap = (x...(x + gw)).any? { |cx| (y...(y + gh)).any? { |cy| occupied.include?([cx, cy]) } }
        unless overlap
          Plant.create(
            garden_id: garden_id, bed_id: bed.id,
            variety_name: variety_name, crop_type: crop_type, source: source,
            lifecycle_stage: "seed_packet",
            grid_x: x, grid_y: y, grid_w: gw, grid_h: gh, quantity: 1
          )
          created += 1
        end
        x += step_x
      end
      y += step_y
    end

    Thread.current[:planner_needs_refresh] = true
    "Filled #{bed_name} with #{created} #{variety_name} (#{crop_type}) at #{step_x}x#{step_y} spacing."
  end
end
