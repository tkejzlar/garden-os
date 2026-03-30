require "ruby_llm"
require "json"
require_relative "../../models/bed"
require_relative "../../models/plant"

class GetGardenOverviewTool < RubyLLM::Tool
  description "Get a high-level overview of the entire garden — all beds with plant counts, empty space percentages, and crop summaries. Use to understand the whole garden before making multi-bed decisions."

  def execute
    garden_id = Thread.current[:current_garden_id]
    beds = Bed.where(garden_id: garden_id).all.map do |bed|
      plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
      total_cells = bed.grid_cols * bed.grid_rows

      occupied = 0
      plants.each { |p| occupied += (p.grid_w || 1) * (p.grid_h || 1) }
      empty_pct = total_cells > 0 ? (((total_cells - occupied).to_f / total_cells) * 100).round(0) : 100

      crops = plants.group_by(&:crop_type).map { |ct, ps| "#{ps.length} #{ct}" }

      {
        name: bed.name,
        bed_type: bed.bed_type,
        grid: "#{bed.grid_cols}x#{bed.grid_rows}",
        plants: plants.length,
        empty_pct: empty_pct,
        crops: crops.join(", "),
        front_edge: (bed.respond_to?(:front_edge) ? bed.front_edge : nil)
      }
    end

    JSON.generate({ total_beds: beds.length, beds: beds })
  end
end
