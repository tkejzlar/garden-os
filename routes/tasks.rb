require_relative "../models/task"

class GardenApp
  post "/tasks/:id/complete" do
    task = Task[params[:id].to_i]
    halt 404 unless task
    task.complete!
    redirect back
  end

  post "/tasks/:id/skip" do
    task = Task[params[:id].to_i]
    halt 404 unless task
    task.update(status: "skipped", updated_at: Time.now)
    redirect back
  end

  post "/tasks/:id/defer" do
    task = Task[params[:id].to_i]
    halt 404 unless task
    task.update(status: "deferred", updated_at: Time.now)
    redirect back
  end

  get "/api/tasks" do
    tasks = Task.where(garden_id: @current_garden.id)
                .exclude(status: "done")
                .order(:due_date).all
    json tasks.map(&:values)
  end

  get "/api/tasks/today" do
    tasks = Task.where(garden_id: @current_garden.id, due_date: Date.today)
                .exclude(status: "done").all
    json tasks.map(&:values)
  end

  post "/api/tasks/:id/snooze" do
    content_type :json
    task = Task[params[:id].to_i]
    halt 404, json(error: "Not found") unless task

    request.body.rewind
    body = begin JSON.parse(request.body.read) rescue {} end
    days = (body["days"] || 1).to_i

    new_date = Date.today + days
    task.update(due_date: new_date, updated_at: Time.now)
    json(ok: true, new_date: new_date.to_s)
  end
end
