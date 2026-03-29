require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/bed_zone"

class ManageZonesTool < RubyLLM::Tool
  description "Create, list, or delete named zones within a bed. Zones define areas like 'rear strip' or 'trellis lane' with a purpose — they help you plan smarter layouts."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :action, type: :string, desc: '"create", "list", or "delete"'
  param :name, type: :string, desc: "Zone name (required for create/delete)"
  param :from_x, type: :string, desc: "Start grid column (create only)"
  param :from_y, type: :string, desc: "Start grid row (create only)"
  param :to_x, type: :string, desc: "End grid column (create only)"
  param :to_y, type: :string, desc: "End grid row (create only)"
  param :purpose, type: :string, desc: "Zone purpose, e.g. 'tall crops', 'border' (create only)"
  param :notes, type: :string, desc: "Additional notes (create only)"

  def execute(bed_name:, action:, name: nil, from_x: nil, from_y: nil, to_x: nil, to_y: nil, purpose: nil, notes: nil)
    return "Error: bed_zones table not yet created — run migrations" unless DB.table_exists?(:bed_zones)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    case action
    when "create"
      return "Error: name, from_x, from_y, to_x, to_y required" unless name && from_x && from_y && to_x && to_y
      BedZone.create(
        bed_id: bed.id, name: name,
        from_x: from_x.to_i, from_y: from_y.to_i,
        to_x: to_x.to_i, to_y: to_y.to_i,
        purpose: purpose, notes: notes,
        created_at: Time.now
      )
      Thread.current[:planner_needs_refresh] = true
      "Created zone '#{name}' on #{bed_name} (#{from_x},#{from_y})→(#{to_x},#{to_y}), purpose: #{purpose || 'general'}."

    when "list"
      zones = BedZone.where(bed_id: bed.id).all
      return "No zones defined for #{bed_name}" if zones.empty?
      zones.map { |z| "- #{z.name}: (#{z.from_x},#{z.from_y})→(#{z.to_x},#{z.to_y}) — #{z.purpose || 'no purpose set'}" }.join("\n")

    when "delete"
      return "Error: name required" unless name
      zone = BedZone.where(bed_id: bed.id, name: name).first
      return "Error: zone '#{name}' not found on #{bed_name}" unless zone
      zone.destroy
      Thread.current[:planner_needs_refresh] = true
      "Deleted zone '#{name}' from #{bed_name}."

    else
      "Error: action must be 'create', 'list', or 'delete'"
    end
  end
end
