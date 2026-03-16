require_relative "../models/task"
require_relative "../models/plant"
require_relative "../models/succession_plan"
require_relative "../db/seeds/seed_varieties"

class TaskGenerator
  def self.generate_all!
    generate_succession_tasks!
    generate_germination_checks!
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
end
