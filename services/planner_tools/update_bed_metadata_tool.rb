require "ruby_llm"
require_relative "../../models/bed"

class UpdateBedMetadataTool < RubyLLM::Tool
  description "Update a bed's environmental metadata — sun exposure, wind, irrigation, and which edge faces the viewer/path. This helps you make better planting decisions."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :sun_exposure, type: :string, desc: '"full", "partial", or "shade" (optional)'
  param :wind_exposure, type: :string, desc: '"sheltered", "moderate", or "exposed" (optional)'
  param :irrigation, type: :string, desc: '"drip", "manual", "sprinkler", or "none" (optional)'
  param :front_edge, type: :string, desc: '"south", "north", "east", "west", or "path" — which side faces viewer (optional)'

  def execute(bed_name:, sun_exposure: nil, wind_exposure: nil, irrigation: nil, front_edge: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    updates = {}
    updates[:sun_exposure] = sun_exposure if sun_exposure
    updates[:wind_exposure] = wind_exposure if wind_exposure
    updates[:irrigation] = irrigation if irrigation
    updates[:front_edge] = front_edge if front_edge

    return "Error: provide at least one field to update" if updates.empty?

    bed.update(updates)
    Thread.current[:planner_needs_refresh] = true
    "Updated #{bed_name}: #{updates.map { |k, v| "#{k}=#{v}" }.join(', ')}."
  end
end
