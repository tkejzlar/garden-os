require "json"
require_relative "../models/bed"
require_relative "../models/plant"
require_relative "../models/task"
require_relative "../models/succession_plan"
require_relative "task_generator"
require_relative "garden_logger"

class PlanCommitter
  def self.commit!(draft, garden_id: nil)
    assignments = draft["assignments"] || []
    successions = draft["successions"] || []
    tasks       = draft["tasks"] || []

    # Fall back to Garden.first if no garden_id provided
    garden_id ||= Garden.first&.id

    # Validate bed references
    errors = validate_beds(assignments, tasks)
    return { success: false, errors: errors } if errors.any?

    counts = { plants: 0, succession_plans: 0, tasks: 0 }

    DB.transaction do
      # Group assignments by bed for auto-slot creation
      assignments.group_by { |a| a["bed_name"] }.each do |bed_name, bed_assignments|
        bed = Bed.where(name: bed_name).first
        next unless bed

        # Auto-place plants on bed grid
        existing_plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
        next_y = existing_plants.any? ? existing_plants.map { |p| (p.grid_y || 0) + (p.grid_h || 1) }.max : 0
        grid_w = 3  # Default: 30cm
        grid_h = 3

        assignments_for_bed = bed_assignments
        assignments_for_bed.each_with_index do |a, i|
          grid_x = (i % [bed.grid_cols / grid_w, 1].max) * grid_w
          grid_y = next_y + (i / [bed.grid_cols / grid_w, 1].max) * grid_h

          Plant.create(
            garden_id: garden_id,
            bed_id: bed.id,
            variety_name: a["variety_name"],
            crop_type: a["crop_type"],
            source: a["source"],
            lifecycle_stage: "seed_packet",
            grid_x: grid_x.clamp(0, bed.grid_cols - 1),
            grid_y: grid_y.clamp(0, bed.grid_rows - 1),
            grid_w: grid_w,
            grid_h: grid_h,
            quantity: a["quantity"]&.to_i || 1
          )
          counts[:plants] += 1
        end
      end

      # Create succession plans + generate tasks
      successions.each do |s|
        plan = SuccessionPlan.create(
          garden_id: garden_id,
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
          garden_id: garden_id,
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

    GardenLogger.info "[PlanCommitter] Committed: #{counts}"
    { success: true, created: counts }
  rescue => e
    GardenLogger.error "[PlanCommitter] Error: #{e.message}"
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
