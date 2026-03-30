require "ruby_llm"
require "json"
require_relative "../../models/bed"
require_relative "../../models/plant"

class DraftVariantsTool < RubyLLM::Tool
  description "Present 2-3 alternative layout variants for the user to compare and choose from. Use this instead of draft_plan when the user asks to compare options, or when you want to offer alternatives (e.g., 'do you prefer dense or spacious?'). Each variant has a name, description, and the same assignments/successions/tasks structure as draft_plan."

  param :payload, type: :string, desc: 'JSON string: { "variants": [{ "name": "Dense potager", "description": "Maximizes yield...", "assignments": [...], "successions": [...], "tasks": [...] }, { "name": "Airy design", "description": "More breathing room...", "assignments": [...] }] }'

  def execute(payload:)
    parsed = JSON.parse(payload)
    variants = parsed["variants"]
    return "Error: provide a 'variants' array with 2-3 options" unless variants.is_a?(Array) && variants.length >= 2

    garden_id = Thread.current[:current_garden_id]
    Thread.current[:planner_variants] = variants

    # Validate each variant
    summaries = variants.map.with_index do |v, i|
      a = v["assignments"]&.length || 0
      s = v["successions"]&.length || 0
      t = v["tasks"]&.length || 0
      warnings = []

      # Check bed references exist
      (v["assignments"] || []).each do |asn|
        bed = Bed.where(name: asn["bed_name"], garden_id: garden_id).first
        warnings << "bed '#{asn['bed_name']}' not found" unless bed
      end

      line = "#{i + 1}. #{v['name']}: #{a} plants, #{s} successions, #{t} tasks"
      line += " [WARNINGS: #{warnings.join('; ')}]" if warnings.any?
      line
    end

    "#{variants.length} layout variants stored:\n#{summaries.join("\n")}\nThe user will see cards for each variant and can pick one to apply."
  rescue JSON::ParserError => e
    "Error: Invalid JSON. #{e.message}"
  end
end
