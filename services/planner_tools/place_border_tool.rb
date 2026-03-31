require "ruby_llm"
require "json"
require "set"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceBorderTool < RubyLLM::Tool
  description "Place plants along the edges of a bed. Use for ornamental borders, companion planting edges, or pest-deterrent rings. Skips cells already occupied."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :edges, type: :string, desc: 'JSON array of edges: "front" (y=0), "back" (y=max), "left" (x=0), "right" (x=max)'
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, edges:, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    edge_list = JSON.parse(edges) rescue []
    return "Error: edges must be a JSON array" if edge_list.empty?

    # Remap edges based on bed front_edge orientation
    fe = (bed.respond_to?(:front_edge) ? bed.front_edge : nil).to_s.downcase
    remap = case fe
    when "south" then { "front" => "back", "back" => "front" }
    when "east"  then { "left" => "right", "right" => "left" }
    when "west"  then { "left" => "right", "right" => "left" }
    else {}
    end
    edge_list = edge_list.map { |e| remap[e] || e }

    gw, gh = Plant.default_grid_size(crop_type)
    step_x = spacing ? spacing.to_i : gw
    step_y = spacing ? spacing.to_i : gh

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

    positions = []

    edge_list.each do |edge|
      case edge
      when "front"
        x = 0
        while x + gw <= bed.grid_cols
          positions << [x, 0] unless occupied.include?([x, 0])
          x += step_x
        end
      when "back"
        y = bed.grid_rows - gh
        x = 0
        while x + gw <= bed.grid_cols
          positions << [x, y] unless occupied.include?([x, y])
          x += step_x
        end
      when "left"
        y = 0
        while y + gh <= bed.grid_rows
          positions << [0, y] unless occupied.include?([0, y])
          y += step_y
        end
      when "right"
        x = bed.grid_cols - gw
        y = 0
        while y + gh <= bed.grid_rows
          positions << [x, y] unless occupied.include?([x, y])
          y += step_y
        end
      end
    end

    positions.uniq!
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
    "Placed #{positions.length} #{variety_name} along #{edge_list.join(', ')} edge(s) of #{bed_name}."
  end
end
