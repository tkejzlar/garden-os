require_relative "../models/succession_plan"
require_relative "../models/task"

class GardenApp
  get "/succession" do
    @plans = SuccessionPlan.all
    require_relative "../models/planner_message"
    @planner_messages = PlannerMessage.order(:created_at).all
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

  # ── Succession Plan CRUD ──────────────────────────────────────────────────

  get "/succession/plans/new" do
    @plan = SuccessionPlan.new
    erb :succession_form
  end

  get "/succession/plans/:id/edit" do
    @plan = SuccessionPlan[params[:id].to_i]
    halt 404 unless @plan
    erb :succession_form
  end

  post "/succession/plans" do
    plan = SuccessionPlan.create(
      crop:                  params[:crop].to_s.strip,
      varieties:             params[:varieties].to_s.split(",").map(&:strip).to_json,
      interval_days:         params[:interval_days].to_i,
      season_start:          params[:season_start].to_s.strip.then { |v| v.empty? ? nil : Date.parse(v) },
      season_end:            params[:season_end].to_s.strip.then { |v| v.empty? ? nil : Date.parse(v) },
      target_beds:           params[:target_beds].to_s.split(",").map(&:strip).to_json,
      total_planned_sowings: params[:total_planned_sowings].to_i
    )
    redirect "/succession"
  end

  patch "/succession/plans/:id" do
    plan = SuccessionPlan[params[:id].to_i]
    halt 404 unless plan

    update = {}
    update[:crop]                  = params[:crop].to_s.strip               if params[:crop]
    update[:varieties]             = params[:varieties].to_s.split(",").map(&:strip).to_json if params[:varieties]
    update[:interval_days]         = params[:interval_days].to_i            if params[:interval_days]
    update[:season_start]          = Date.parse(params[:season_start])      if params[:season_start] && !params[:season_start].empty?
    update[:season_end]            = Date.parse(params[:season_end])        if params[:season_end] && !params[:season_end].empty?
    update[:target_beds]           = params[:target_beds].to_s.split(",").map(&:strip).to_json if params[:target_beds]
    update[:total_planned_sowings] = params[:total_planned_sowings].to_i    if params[:total_planned_sowings]

    plan.update(update)
    redirect "/succession"
  end

  delete "/succession/plans/:id" do
    plan = SuccessionPlan[params[:id].to_i]
    halt 404 unless plan
    plan.destroy
    redirect "/succession"
  end

  # ── Generate tasks for a single plan ──────────────────────────────────────

  post "/succession/plans/:id/generate" do
    plan = SuccessionPlan[params[:id].to_i]
    halt 404 unless plan

    require_relative "../services/task_generator"
    TaskGenerator.generate_for_plan!(plan)
    redirect "/succession"
  end

  # ── Manual task creation ──────────────────────────────────────────────────

  post "/succession/tasks" do
    Task.create(
      title:     params[:title].to_s.strip,
      task_type: params[:task_type] || "sow",
      due_date:  params[:due_date].to_s.strip.then { |v| v.empty? ? nil : Date.parse(v) },
      priority:  params[:priority] || "should",
      status:    "upcoming",
      notes:     params[:notes].to_s.strip.then { |v| v.empty? ? nil : v }
    )
    redirect "/succession"
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

  # ── AI Planner Chat ──────────────────────────────────────────────────────

  # Non-streaming fallback
  post "/succession/planner/message" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    message = body["message"].to_s.strip
    halt 400, json(error: "message required") if message.empty?

    require_relative "../services/planner_service"
    service = PlannerService.new
    result = service.send_message(message)

    json({
      content: result[:content],
      draft: result[:draft],
      tool_calls: result[:tool_calls]
    })
  end

  # SSE streaming endpoint
  get "/succession/planner/stream" do
    message = params[:message].to_s.strip
    halt 400, "message required" if message.empty?

    require_relative "../services/planner_service"

    content_type "text/event-stream"
    headers "Cache-Control" => "no-cache", "Connection" => "keep-alive"

    stream(:keep_open) do |out|
      service = PlannerService.new

      service.send_message_streaming(message) do |event|
        case event[:type]
        when "chunk"
          out << "data: #{JSON.generate({ type: "chunk", content: event[:content] })}\n\n"
        when "draft"
          out << "data: #{JSON.generate({ type: "draft", draft: event[:draft] })}\n\n"
        when "done"
          out << "data: #{JSON.generate({ type: "done" })}\n\n"
          out.close
        when "error"
          out << "data: #{JSON.generate({ type: "error", content: event[:content] })}\n\n"
          out.close
        end
      end
    rescue => e
      require_relative "../services/garden_logger"
      GardenLogger.error "[Planner/SSE] Stream error: #{e.message}"
      out << "data: #{JSON.generate({ type: "error", content: e.message })}\n\n" rescue nil
      out.close rescue nil
    end
  end

  post "/succession/planner/commit" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    draft = body["draft_payload"]
    halt 400, json(error: "draft_payload required") unless draft.is_a?(Hash)

    require_relative "../services/plan_committer"
    result = PlanCommitter.commit!(draft)
    json result
  end

  delete "/succession/planner/messages" do
    require_relative "../models/planner_message"
    PlannerMessage.dataset.delete
    json(success: true)
  end
end
