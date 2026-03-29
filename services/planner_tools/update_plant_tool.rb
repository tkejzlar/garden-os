require "ruby_llm"
require_relative "../../models/plant"

class UpdatePlantTool < RubyLLM::Tool
  description "Update a plant's grid position, size, quantity, or names. Use for fine-tuning placement after initial layout."

  param :plant_id, type: :string, desc: "ID of the plant to update"
  param :grid_x, type: :string, desc: "New grid column (optional)"
  param :grid_y, type: :string, desc: "New grid row (optional)"
  param :grid_w, type: :string, desc: "New grid width in cells (optional)"
  param :grid_h, type: :string, desc: "New grid height in cells (optional)"
  param :quantity, type: :string, desc: "New quantity (optional)"
  param :variety_name, type: :string, desc: "New variety name (optional)"
  param :crop_type, type: :string, desc: "New crop type (optional)"

  def execute(plant_id:, grid_x: nil, grid_y: nil, grid_w: nil, grid_h: nil, quantity: nil, variety_name: nil, crop_type: nil)
    garden_id = Thread.current[:current_garden_id]
    plant = Plant[plant_id.to_i]
    return "Error: plant not found" unless plant && plant.garden_id == garden_id

    updates = {}
    updates[:grid_x] = grid_x.to_i if grid_x
    updates[:grid_y] = grid_y.to_i if grid_y
    updates[:grid_w] = grid_w.to_i if grid_w
    updates[:grid_h] = grid_h.to_i if grid_h
    updates[:quantity] = quantity.to_i if quantity
    updates[:variety_name] = variety_name if variety_name
    updates[:crop_type] = crop_type if crop_type
    updates[:updated_at] = Time.now

    return "Error: nothing to update" if updates.length == 1

    plant.update(updates)
    Thread.current[:planner_needs_refresh] = true
    "Updated #{plant.variety_name}: #{updates.reject { |k, _| k == :updated_at }.map { |k, v| "#{k}=#{v}" }.join(', ')}"
  end
end
