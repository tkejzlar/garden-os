require "ruby_llm"
require_relative "../../models/succession_plan"

class DeduplicateSuccessionPlansTool < RubyLLM::Tool
  description "Find and merge duplicate succession plans for the same crop (case-insensitive). Keeps the oldest plan, merges varieties and target beds from duplicates, then deletes the duplicates."

  param :crop, type: :string, desc: "Crop name to deduplicate (optional — deduplicates all if omitted)"

  def execute(crop: nil)
    garden_id = Thread.current[:current_garden_id]
    plans = SuccessionPlan.where(garden_id: garden_id).all

    # Group by lowercase crop name
    groups = plans.group_by { |p| p.crop.downcase.strip }
    groups = groups.select { |k, _| k == crop.downcase.strip } if crop

    merged = 0
    groups.each do |_key, group|
      next if group.length <= 1

      # Keep oldest, merge others into it
      keeper = group.sort_by { |p| p.id }.first
      dupes = group.sort_by { |p| p.id }[1..]

      all_varieties = ([keeper.varieties_list] + dupes.map(&:varieties_list)).flatten.uniq
      all_beds = ([keeper.target_beds_list] + dupes.map(&:target_beds_list)).flatten.uniq

      keeper.update(
        varieties: all_varieties.to_json,
        target_beds: all_beds.to_json
      )

      dupes.each do |d|
        d.destroy
        merged += 1
      end
    end

    return "No duplicate succession plans found." if merged == 0

    Thread.current[:planner_needs_refresh] = true
    "Merged #{merged} duplicate succession plan(s). Varieties and target beds combined into the primary plan."
  end
end
