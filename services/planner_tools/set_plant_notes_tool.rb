require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class SetPlantNotesTool < RubyLLM::Tool
  description "Set design-intent notes on a plant. Use to annotate placement decisions like 'let spill over edge' or 'harvest before canopy closes'. Find by plant ID or bed+variety."

  param :plant_id, type: :string, desc: "Plant ID (optional if bed_name+variety_name given)"
  param :bed_name, type: :string, desc: "Bed name (optional if plant_id given)"
  param :variety_name, type: :string, desc: "Variety name (optional if plant_id given)"
  param :notes, type: :string, desc: "The note to set"

  def execute(notes:, plant_id: nil, bed_name: nil, variety_name: nil)
    garden_id = Thread.current[:current_garden_id]

    if plant_id
      plant = Plant[plant_id.to_i]
      return "Error: plant not found" unless plant && plant.garden_id == garden_id
    elsif bed_name && variety_name
      bed = Bed.where(name: bed_name, garden_id: garden_id).first
      return "Error: bed '#{bed_name}' not found" unless bed
      plant = Plant.where(bed_id: bed.id, variety_name: variety_name).exclude(lifecycle_stage: "done").first
      return "Error: #{variety_name} not found on #{bed_name}" unless plant
    else
      return "Error: provide plant_id or bed_name+variety_name"
    end

    plant.update(notes: notes, updated_at: Time.now)
    "Set note on #{plant.variety_name}: \"#{notes}\""
  end
end
