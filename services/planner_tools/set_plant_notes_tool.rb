require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class SetPlantNotesTool < RubyLLM::Tool
  description "Set design-intent notes on a plant. Use to annotate placement decisions like 'let spill over edge' or 'harvest before canopy closes'. Find by plant ID or bed+variety or bed+crop_type."

  param :plant_id, type: :string, desc: "Plant ID (optional if bed_name+variety_name or bed_name+crop_type given)"
  param :bed_name, type: :string, desc: "Bed name (optional if plant_id given)"
  param :variety_name, type: :string, desc: "Variety name (optional if plant_id given)"
  param :crop_type, type: :string, desc: "Crop type to match (optional, used if no variety_name)"
  param :notes, type: :string, desc: "The note to set"

  def execute(notes:, plant_id: nil, bed_name: nil, variety_name: nil, crop_type: nil)
    garden_id = Thread.current[:current_garden_id]

    if plant_id
      plant = Plant[plant_id.to_i]
      return "Error: plant not found" unless plant && plant.garden_id == garden_id
      plant.update(notes: notes, updated_at: Time.now)
      return "Set note on #{plant.variety_name}: \"#{notes}\""
    end

    return "Error: provide plant_id, or bed_name with variety_name or crop_type" unless bed_name && (variety_name || crop_type)

    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    scope = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done")
    scope = scope.where(variety_name: variety_name) if variety_name
    scope = scope.where(crop_type: crop_type) if crop_type && !variety_name

    plants = scope.all
    return "Error: no matching plants found on #{bed_name}" if plants.empty?

    plants.each { |p| p.update(notes: notes, updated_at: Time.now) }
    "Set note on #{plants.length} plant(s) on #{bed_name}: \"#{notes}\""
  end
end
