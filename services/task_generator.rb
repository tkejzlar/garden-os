require_relative "../models/task"
require_relative "../models/plant"
require_relative "../models/succession_plan"
require_relative "../db/seeds/seed_varieties"
require_relative "sensor_service"

class TaskGenerator
  def self.generate_all!
    generate_succession_tasks!
    generate_germination_checks!
    auto_skip_watering_tasks!
  end

  def self.generate_succession_tasks!
    SuccessionPlan.all.each do |sp|
      next if sp.season_end && sp.season_end < Date.today

      existing = Task.where(task_type: "sow")
                     .where(Sequel.like(:title, "%#{sp.crop}%")).count

      next if existing >= sp.total_planned_sowings.to_i

      next_date = sp.next_sowing_date(existing)
      next if next_date.nil? || next_date > Date.today + 14

      already_exists = Task.where(task_type: "sow")
                           .where(Sequel.like(:title, "%#{sp.crop}%"))
                           .exclude(status: "done")
                           .where(due_date: (next_date - 14)..(next_date + 14))
                           .any?
      next if already_exists

      beds_str = sp.target_beds_list.join(", ")
      Task.create(
        title: "Sow #{sp.crop} ##{existing + 1} — #{beds_str}",
        task_type: "sow",
        due_date: next_date,
        priority: "should",
        status: "upcoming",
        notes: "Varieties: #{sp.varieties_list.join(', ')}. Succession #{existing + 1} of #{sp.total_planned_sowings}."
      )
    end
  end

  def self.generate_germination_checks!
    Plant.where(lifecycle_stage: "germinating").all.each do |plant|
      days = plant.days_in_stage
      variety_info = Varieties.for(plant.crop_type)
      next unless variety_info

      max_days = variety_info["germination_days_max"] || 14
      if days >= (max_days * 0.5).to_i
        already_exists = Task.where(task_type: "check")
                             .where(Sequel.like(:title, "%#{plant.variety_name}%"))
                             .exclude(status: "done")
                             .any?
        next if already_exists

        Task.create(
          title: "Check #{plant.variety_name} — day #{days} germinating",
          task_type: "check",
          due_date: Date.today,
          priority: "should",
          status: "upcoming",
          notes: "Expected #{variety_info['germination_days_min']}-#{max_days} days. Currently day #{days}."
        )
      end
    end
  end

  def self.auto_skip_watering_tasks!
    return unless sensor_skip_conditions_met?

    reason = build_skip_reason
    Task.where(task_type: "water")
        .exclude(status: %w[done skipped])
        .each do |task|
          task.update(status: "skipped", notes: [task.notes, reason].compact.join(" | "))
        end
  end

  # Generate tasks for a single succession plan (called from UI "Generate" button)
  def self.generate_for_plan!(sp)
    return if sp.season_end && sp.season_end < Date.today

    existing = Task.where(task_type: "sow")
                   .where(Sequel.like(:title, "%#{sp.crop}%")).count

    total = sp.total_planned_sowings.to_i
    return if existing >= total

    # Generate ALL remaining tasks for this plan (not just the next 14 days)
    beds_str = sp.target_beds_list.join(", ")
    (existing...total).each do |i|
      next_date = sp.next_sowing_date(i)
      next if next_date.nil?

      already_exists = Task.where(task_type: "sow")
                           .where(Sequel.like(:title, "%#{sp.crop}%"))
                           .where(due_date: (next_date - 3)..(next_date + 3))
                           .any?
      next if already_exists

      Task.create(
        title: "Sow #{sp.crop} ##{i + 1} — #{beds_str}",
        task_type: "sow",
        due_date: next_date,
        priority: "should",
        status: "upcoming",
        notes: "Varieties: #{sp.varieties_list.join(', ')}. Succession #{i + 1} of #{total}."
      )
    end
  end

  # ---- private helpers -------------------------------------------------------

  def self.sensor_skip_conditions_met?
    SensorService.rain_detected? || SensorService.irrigation_active?
  rescue => e
    warn "TaskGenerator sensor check error: #{e.message}"
    false
  end

  def self.build_skip_reason
    if SensorService.rain_detected?
      "Auto-skipped: rain detected"
    elsif SensorService.irrigation_active?
      "Auto-skipped: irrigation active"
    else
      "Auto-skipped: sensor condition"
    end
  end
end
