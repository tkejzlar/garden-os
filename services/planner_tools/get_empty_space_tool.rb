require "ruby_llm"
require "set"
require_relative "../../models/bed"
require_relative "../../models/plant"

class GetEmptySpaceTool < RubyLLM::Tool
  description "Report empty space on a bed — total empty percentage and largest contiguous gaps with their positions. Use before placing to understand what fits where."

  param :bed_name, type: :string, desc: "Exact bed name"

  def execute(bed_name:)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    cols = bed.grid_cols
    rows = bed.grid_rows
    total = cols * rows

    occupied = Set.new
    Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all.each do |p|
      (p.grid_x...(p.grid_x + p.grid_w)).each do |cx|
        (p.grid_y...(p.grid_y + p.grid_h)).each do |cy|
          occupied.add([cx, cy]) if cx < cols && cy < rows
        end
      end
    end

    empty_count = total - occupied.length
    pct = ((empty_count.to_f / total) * 100).round(0)

    # Find largest empty rectangles using greedy scan
    gaps = find_gaps(cols, rows, occupied)

    lines = ["#{bed_name}: #{pct}% empty (#{empty_count} of #{total} cells, grid #{cols}x#{rows})"]
    if gaps.any?
      lines << "Largest gaps:"
      gaps.first(5).each do |g|
        area = g[:w] * g[:h]
        lines << "  (#{g[:x]},#{g[:y]})→(#{g[:x] + g[:w]},#{g[:y] + g[:h]}): #{area} cells (#{g[:w]}x#{g[:h]})"
      end
    end

    lines.join("\n")
  end

  private

  def find_gaps(cols, rows, occupied)
    # Build boolean grid (true = free)
    free = Array.new(rows) { |r| Array.new(cols) { |c| !occupied.include?([c, r]) } }

    gaps = []
    visited = Set.new

    # Scan for rectangular gaps using greedy expansion
    rows.times do |y|
      cols.times do |x|
        next unless free[y][x] && !visited.include?([x, y])

        # Expand right
        max_w = 0
        while x + max_w < cols && free[y][x + max_w]
          max_w += 1
        end

        # Expand down maintaining width
        max_h = 0
        while y + max_h < rows
          row_ok = (x...(x + max_w)).all? { |cx| free[y + max_h][cx] }
          break unless row_ok
          max_h += 1
        end

        if max_w > 0 && max_h > 0
          gaps << { x: x, y: y, w: max_w, h: max_h }
          # Mark as visited
          (x...(x + max_w)).each do |cx|
            (y...(y + max_h)).each do |cy|
              visited.add([cx, cy])
            end
          end
        end
      end
    end

    gaps.sort_by { |g| -(g[:w] * g[:h]) }
  end
end
