require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class AlignPlantsTool < RubyLLM::Tool
  description "Align or distribute existing plants on a bed. Operations: align-left, align-right, align-top, align-bottom, center-h, center-v, distribute-h, distribute-v, compact."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :operation, type: :string, desc: '"align-left", "align-right", "align-top", "align-bottom", "center-h", "center-v", "distribute-h", "distribute-v", "compact"'
  param :filter_variety, type: :string, desc: "Only affect plants with this variety (optional)"
  param :filter_crop_type, type: :string, desc: "Only affect plants with this crop type (optional)"

  def execute(bed_name:, operation:, filter_variety: nil, filter_crop_type: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    scope = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done")
    scope = scope.where(variety_name: filter_variety) if filter_variety
    scope = scope.where(crop_type: filter_crop_type) if filter_crop_type
    plants = scope.all
    return "No matching plants on #{bed_name}" if plants.empty?

    case operation
    when "align-left"
      min_x = plants.map(&:grid_x).min
      plants.each { |p| p.update(grid_x: min_x, updated_at: Time.now) }

    when "align-right"
      max_right = plants.map { |p| p.grid_x + p.grid_w }.max
      plants.each { |p| p.update(grid_x: max_right - p.grid_w, updated_at: Time.now) }

    when "align-top"
      min_y = plants.map(&:grid_y).min
      plants.each { |p| p.update(grid_y: min_y, updated_at: Time.now) }

    when "align-bottom"
      max_bottom = plants.map { |p| p.grid_y + p.grid_h }.max
      plants.each { |p| p.update(grid_y: max_bottom - p.grid_h, updated_at: Time.now) }

    when "center-h"
      plants.each do |p|
        cx = (bed.grid_cols - p.grid_w) / 2
        p.update(grid_x: cx.clamp(0, bed.grid_cols - p.grid_w), updated_at: Time.now)
      end

    when "center-v"
      plants.each do |p|
        cy = (bed.grid_rows - p.grid_h) / 2
        p.update(grid_y: cy.clamp(0, bed.grid_rows - p.grid_h), updated_at: Time.now)
      end

    when "distribute-h"
      sorted = plants.sort_by(&:grid_x)
      return "Need 2+ plants to distribute" if sorted.length < 2
      total_plant_w = sorted.sum(&:grid_w)
      total_space = bed.grid_cols - total_plant_w
      gap = total_space.to_f / (sorted.length - 1)
      x = 0
      sorted.each_with_index do |p, i|
        p.update(grid_x: x.round.clamp(0, bed.grid_cols - p.grid_w), updated_at: Time.now)
        x += p.grid_w + gap
      end

    when "distribute-v"
      sorted = plants.sort_by(&:grid_y)
      return "Need 2+ plants to distribute" if sorted.length < 2
      total_plant_h = sorted.sum(&:grid_h)
      total_space = bed.grid_rows - total_plant_h
      gap = total_space.to_f / (sorted.length - 1)
      y = 0
      sorted.each_with_index do |p, i|
        p.update(grid_y: y.round.clamp(0, bed.grid_rows - p.grid_h), updated_at: Time.now)
        y += p.grid_h + gap
      end

    when "compact"
      sorted = plants.sort_by { |p| [p.grid_y, p.grid_x] }
      cursor_x = 0
      cursor_y = 0
      row_h = 0
      sorted.each do |p|
        if cursor_x + p.grid_w > bed.grid_cols
          cursor_x = 0
          cursor_y += row_h
          row_h = 0
        end
        p.update(grid_x: cursor_x, grid_y: cursor_y, updated_at: Time.now)
        cursor_x += p.grid_w
        row_h = [row_h, p.grid_h].max
      end

    else
      return "Error: unknown operation '#{operation}'"
    end

    Thread.current[:planner_needs_refresh] = true
    "#{operation}: adjusted #{plants.length} plants on #{bed_name}."
  end
end
