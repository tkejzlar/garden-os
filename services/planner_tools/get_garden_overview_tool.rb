require "ruby_llm"
require "json"
require_relative "../../models/bed"
require_relative "../../models/plant"

class GetGardenOverviewTool < RubyLLM::Tool
  description "Get a high-level overview of the entire garden — all beds with plant counts, empty space percentages, and crop summaries. Use to understand the whole garden before making multi-bed decisions."

  def execute
    garden_id = Thread.current[:current_garden_id]
    beds = Bed.where(garden_id: garden_id).order(:position, :name).all

    lines = ["## Garden Overview\n"]
    lines << "| Bed | Plants | Empty | Top Crops |"
    lines << "|-----|--------|-------|-----------|"

    beds.each do |bed|
      plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
      total_cells = bed.grid_cols * bed.grid_rows
      occupied = plants.sum { |p| (p.grid_w || 1) * (p.grid_h || 1) }
      empty_pct = total_cells > 0 ? (((total_cells - occupied).to_f / total_cells) * 100).round(0) : 100

      crops = plants.group_by(&:crop_type).map { |ct, ps| "#{ps.length} #{ct}" }.first(3)
      fe = (bed.respond_to?(:front_edge) ? bed.front_edge : nil)
      bed_label = bed.name
      bed_label += " (#{fe})" if fe

      lines << "| #{bed_label} | #{plants.length} | #{empty_pct}% | #{crops.join(', ')} |"
    end

    total_plants = Plant.where(bed_id: beds.map(&:id)).exclude(lifecycle_stage: "done").count
    total_beds = beds.length
    lines << "\n**Total:** #{total_plants} plants across #{total_beds} beds"

    lines.join("\n")
  end
end
