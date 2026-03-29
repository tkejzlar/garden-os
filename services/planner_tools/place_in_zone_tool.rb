require "ruby_llm"
require "set"
require_relative "../../models/bed"
require_relative "../../models/bed_zone"
require_relative "../../models/plant"

class PlaceInZoneTool < RubyLLM::Tool
  description "Place plants within a named bed zone. Strategies: 'fill' (fill zone), 'row' (horizontal row through center), 'column' (vertical column through center), 'border' (along zone edges), 'center' (one plant centered)."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :zone_name, type: :string, desc: "Name of the zone within the bed"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :strategy, type: :string, desc: '"fill", "row", "column", "border", or "center"'
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, zone_name:, variety_name:, crop_type:, strategy:, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed
    return "Error: bed_zones table not available" unless DB.table_exists?(:bed_zones)

    zone = BedZone.where(bed_id: bed.id, name: zone_name).first
    return "Error: zone '#{zone_name}' not found on #{bed_name}" unless zone

    gw, gh = Plant.default_grid_size(crop_type)
    step_x = spacing ? spacing.to_i : gw
    step_y = spacing ? spacing.to_i : gh

    existing = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    occupied = Set.new
    existing.each do |p|
      (p.grid_x...(p.grid_x + p.grid_w)).each do |cx|
        (p.grid_y...(p.grid_y + p.grid_h)).each do |cy|
          occupied.add([cx, cy])
        end
      end
    end

    positions = case strategy
    when "fill"
      pos = []
      y = zone.from_y
      while y + gh <= zone.to_y
        x = zone.from_x
        while x + gw <= zone.to_x
          overlap = (x...(x + gw)).any? { |cx| (y...(y + gh)).any? { |cy| occupied.include?([cx, cy]) } }
          pos << [x, y] unless overlap
          x += step_x
        end
        y += step_y
      end
      pos
    when "row"
      mid_y = zone.from_y + (zone.to_y - zone.from_y - gh) / 2
      pos = []
      x = zone.from_x
      while x + gw <= zone.to_x
        pos << [x, mid_y] unless occupied.include?([x, mid_y])
        x += step_x
      end
      pos
    when "column"
      mid_x = zone.from_x + (zone.to_x - zone.from_x - gw) / 2
      pos = []
      y = zone.from_y
      while y + gh <= zone.to_y
        pos << [mid_x, y] unless occupied.include?([mid_x, y])
        y += step_y
      end
      pos
    when "border"
      pos = []
      x = zone.from_x
      while x + gw <= zone.to_x
        pos << [x, zone.from_y] unless occupied.include?([x, zone.from_y])
        y_bot = zone.to_y - gh
        pos << [x, y_bot] unless occupied.include?([x, y_bot]) || y_bot == zone.from_y
        x += step_x
      end
      y = zone.from_y + step_y
      while y + gh <= zone.to_y - gh
        pos << [zone.from_x, y] unless occupied.include?([zone.from_x, y])
        x_r = zone.to_x - gw
        pos << [x_r, y] unless occupied.include?([x_r, y]) || x_r == zone.from_x
        y += step_y
      end
      pos.uniq
    when "center"
      cx = zone.from_x + (zone.to_x - zone.from_x - gw) / 2
      cy = zone.from_y + (zone.to_y - zone.from_y - gh) / 2
      overlap = (cx...(cx + gw)).any? { |x| (cy...(cy + gh)).any? { |y| occupied.include?([x, y]) } }
      overlap ? [] : [[cx, cy]]
    else
      return "Error: strategy must be 'fill', 'row', 'column', 'border', or 'center'"
    end

    positions.select! { |x, y| bed.point_in_polygon?(x, y) }
    positions.each do |x, y|
      Plant.create(
        garden_id: garden_id, bed_id: bed.id,
        variety_name: variety_name, crop_type: crop_type, source: source,
        lifecycle_stage: "seed_packet",
        grid_x: x, grid_y: y, grid_w: gw, grid_h: gh, quantity: 1
      )
    end

    Thread.current[:planner_needs_refresh] = true
    "Placed #{positions.length} #{variety_name} in zone '#{zone_name}' (#{strategy}) on #{bed_name}."
  end
end
