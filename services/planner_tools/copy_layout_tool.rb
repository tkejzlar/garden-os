require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class CopyLayoutTool < RubyLLM::Tool
  description "Copy or mirror a bed's plant layout to another bed. Modes: 'copy' (same positions), 'mirror-h' (flip left-right), 'mirror-v' (flip top-bottom). Optionally clear target bed first."

  param :source_bed, type: :string, desc: "Bed to copy from"
  param :target_bed, type: :string, desc: "Bed to copy to"
  param :mode, type: :string, desc: '"copy", "mirror-h", or "mirror-v"'
  param :clear_target, type: :string, desc: '"true" to clear target bed first (optional)'

  def execute(source_bed:, target_bed:, mode:, clear_target: nil)
    garden_id = Thread.current[:current_garden_id]
    src = Bed.where(name: source_bed, garden_id: garden_id).first
    return "Error: source bed '#{source_bed}' not found" unless src
    tgt = Bed.where(name: target_bed, garden_id: garden_id).first
    return "Error: target bed '#{target_bed}' not found" unless tgt

    src_plants = Plant.where(bed_id: src.id).exclude(lifecycle_stage: "done").all
    return "No plants on #{source_bed} to copy" if src_plants.empty?

    if clear_target == "true"
      Plant.where(bed_id: tgt.id).exclude(lifecycle_stage: "done").all.each(&:destroy)
    end

    created = 0
    src_plants.each do |p|
      case mode
      when "copy"
        new_x = p.grid_x
        new_y = p.grid_y
      when "mirror-h"
        new_x = tgt.grid_cols - p.grid_x - p.grid_w
        new_y = p.grid_y
      when "mirror-v"
        new_x = p.grid_x
        new_y = tgt.grid_rows - p.grid_y - p.grid_h
      else
        return "Error: mode must be 'copy', 'mirror-h', or 'mirror-v'"
      end

      next if new_x < 0 || new_y < 0 || new_x + p.grid_w > tgt.grid_cols || new_y + p.grid_h > tgt.grid_rows

      Plant.create(
        garden_id: garden_id, bed_id: tgt.id,
        variety_name: p.variety_name, crop_type: p.crop_type, source: p.source,
        lifecycle_stage: "seed_packet",
        grid_x: new_x, grid_y: new_y, grid_w: p.grid_w, grid_h: p.grid_h,
        quantity: p.quantity
      )
      created += 1
    end

    Thread.current[:planner_needs_refresh] = true
    "#{mode}: copied #{created} plants from #{source_bed} to #{target_bed}."
  end
end
