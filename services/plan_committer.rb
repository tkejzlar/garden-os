require "json"
require_relative "../models/bed"
require_relative "../models/plant"
require_relative "../models/task"
require_relative "../models/succession_plan"
require_relative "task_generator"

class PlanCommitter
  def self.commit!(draft)
    assignments = draft["assignments"] || []
    successions = draft["successions"] || []
    tasks       = draft["tasks"] || []

    # Validate bed references
    errors = validate_beds(assignments, tasks)
    return { success: false, errors: errors } if errors.any?

    counts = { plants: 0, succession_plans: 0, tasks: 0 }

    DB.transaction do
      # Create plants from assignments
      assignments.each do |a|
        bed = Bed.where(name: a["bed_name"]).first
        row = bed ? Row.where(bed_id: bed.id, name: a["row_name"]).first : nil
        slot = row ? Slot.where(row_id: row.id, position: a["slot_position"]).first : nil

        Plant.create(
          variety_name: a["variety_name"],
          crop_type: a["crop_type"],
          source: a["source"],
          slot_id: slot&.id,
          lifecycle_stage: "seed_packet"
        )
        counts[:plants] += 1
      end

      # Create succession plans + generate tasks
      successions.each do |s|
        plan = SuccessionPlan.create(
          crop: s["crop"],
          varieties: (s["varieties"] || []).to_json,
          interval_days: s["interval_days"].to_i,
          season_start: s["season_start"] ? Date.parse(s["season_start"]) : nil,
          season_end: s["season_end"] ? Date.parse(s["season_end"]) : nil,
          total_planned_sowings: s["total_sowings"].to_i,
          target_beds: (s["target_beds"] || []).to_json
        )
        TaskGenerator.generate_for_plan!(plan)
        counts[:succession_plans] += 1
        counts[:tasks] += Task.where(task_type: "sow")
                              .where(Sequel.like(:title, "%#{plan.crop}%")).count
      end

      # Create explicit tasks
      tasks.each do |t|
        task = Task.create(
          title: t["title"],
          task_type: t["task_type"] || "sow",
          due_date: t["due_date"] ? Date.parse(t["due_date"]) : nil,
          priority: t["priority"] || "should",
          status: "upcoming",
          notes: t["notes"]
        )
        (t["related_beds"] || []).each do |bed_name|
          bed = Bed.where(name: bed_name).first
          DB[:tasks_beds].insert(task_id: task.id, bed_id: bed.id) if bed
        end
        counts[:tasks] += 1
      end
    end

    { success: true, created: counts }
  rescue => e
    { success: false, errors: ["Commit failed: #{e.message}"] }
  end

  private

  def self.validate_beds(assignments, tasks)
    errors = []
    bed_names = (assignments.map { |a| a["bed_name"] } +
                 tasks.flat_map { |t| t["related_beds"] || [] }).compact.uniq

    bed_names.each do |name|
      errors << "Bed '#{name}' not found" unless Bed.where(name: name).any?
    end

    errors
  end
end
