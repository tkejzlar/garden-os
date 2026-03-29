require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class RemovePlantsTool < RubyLLM::Tool
  description "Remove specific plants from a bed by variety name, crop type, or plant IDs. Use for targeted cleanup — removing duplicates, unwanted varieties, etc."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Remove all plants with this variety name (optional)"
  param :crop_type, type: :string, desc: "Remove all plants with this crop type (optional)"
  param :plant_ids, type: :string, desc: "JSON array of plant IDs to remove (optional)"

  def execute(bed_name:, variety_name: nil, crop_type: nil, plant_ids: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    scope = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done")

    if plant_ids
      ids = JSON.parse(plant_ids) rescue []
      scope = scope.where(id: ids)
    elsif variety_name
      scope = scope.where(variety_name: variety_name)
    elsif crop_type
      scope = scope.where(crop_type: crop_type)
    else
      return "Error: provide variety_name, crop_type, or plant_ids"
    end

    plants = scope.all
    count = plants.length
    removed = plants.map { |p| "#{p.variety_name} (#{p.crop_type})" }
    plants.each(&:destroy)

    Thread.current[:planner_needs_refresh] = true
    "Removed #{count} plants from #{bed_name}: #{removed.join(', ')}"
  end
end
