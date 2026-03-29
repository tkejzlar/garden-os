require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class DeduplicateBedTool < RubyLLM::Tool
  description "Find and remove duplicate plants on a bed (same variety + crop type). Keeps the oldest of each group. Use after repeated draft applications that created duplicates."

  param :bed_name, type: :string, desc: "Exact bed name"

  def execute(bed_name:)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").order(:created_at).all
    groups = plants.group_by { |p| [p.variety_name, p.crop_type] }

    removed = 0
    groups.each do |_key, group|
      next if group.length <= 1
      group[1..].each do |dup|
        dup.destroy
        removed += 1
      end
    end

    return "No duplicates found on #{bed_name}." if removed == 0

    Thread.current[:planner_needs_refresh] = true
    "Removed #{removed} duplicate(s) from #{bed_name}. Kept oldest of each variety."
  end
end
