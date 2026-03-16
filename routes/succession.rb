require_relative "../models/succession_plan"
require_relative "../models/task"

class GardenApp
  get "/succession" do
    @plans = SuccessionPlan.all
    erb :succession
  end

  get "/api/succession/gantt" do
    today = Date.today

    plans = SuccessionPlan.all.map do |sp|
      # Fetch all sow tasks whose title contains the crop name, ordered by due_date
      sow_tasks = Task
        .where(task_type: "sow")
        .where(Sequel.like(:title, "%#{sp.crop}%"))
        .order(:due_date)
        .all

      bars = sow_tasks.each_with_index.map do |task, idx|
        days_until = task.due_date ? (task.due_date - today).to_i : nil
        color =
          if task.status == "done"
            "green"
          elsif days_until && days_until <= 7
            "amber"
          else
            "gray"
          end

        {
          task_id:    task.id,
          label:      "Sow ##{idx + 1}",
          due_date:   task.due_date&.to_s,
          status:     task.status,
          color:      color,
          days_until: days_until
        }
      end

      {
        plan_id:         sp.id,
        crop:            sp.crop,
        varieties:       sp.varieties_list,
        target_beds:     sp.target_beds_list,
        interval_days:   sp.interval_days,
        season_start:    sp.season_start&.to_s,
        season_end:      sp.season_end&.to_s,
        total_sowings:   sp.total_planned_sowings || 0,
        bars:            bars
      }
    end

    json({ today: today.to_s, plans: plans })
  end

  get "/api/succession" do
    plans = SuccessionPlan.all.map do |sp|
      completed = Task.where(task_type: "sow")
                      .where(Sequel.like(:title, "%#{sp.crop}%"))
                      .where(status: "done").count
      upcoming = Task.where(task_type: "sow")
                     .where(Sequel.like(:title, "%#{sp.crop}%"))
                     .exclude(status: "done").first

      sp.values.merge(
        completed_sowings: completed,
        next_sowing: upcoming&.values,
        next_sowing_date: sp.next_sowing_date(completed)&.to_s
      )
    end
    json plans
  end

  patch "/tasks/:id/reschedule" do
    task = Task[params[:id].to_i]
    halt 404, json(error: "Task not found") unless task

    new_date = params[:due_date]
    halt 422, json(error: "due_date required") if new_date.nil? || new_date.strip.empty?

    begin
      parsed = Date.parse(new_date)
    rescue ArgumentError
      halt 422, json(error: "Invalid date format")
    end

    task.update(due_date: parsed, updated_at: Time.now)
    json task.values.merge(due_date: task.due_date.to_s)
  end
end
