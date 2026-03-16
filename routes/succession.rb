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

  # SSE streaming endpoint — background thread + queue to avoid Puma write timeout
  get "/succession/planner/stream" do
    message = params[:message].to_s.strip
    halt 400, "message required" if message.empty?

    require_relative "../services/planner_service"
    require_relative "../services/garden_logger"

    # Queue bridges the background AI thread and the SSE response
    queue = Thread::Queue.new

    # Run AI in background thread — pushes events to queue
    ai_thread = Thread.new do
      begin
        service = PlannerService.new
        service.send_message_streaming(message) do |event|
          queue.push(event)
        end
      rescue => e
        GardenLogger.error "[Planner/SSE] AI thread error: #{e.class}: #{e.message}"
        queue.push({ type: "error", content: e.message })
      end
      queue.push(:done)
    end

    # SSE body reads from queue, sends keepalives while waiting
    sse_body = Enumerator.new do |yielder|
      yielder << ": connected\n\n"

      loop do
        # Non-blocking poll with 2s timeout — yields keepalive if nothing ready
        event = nil
        begin
          event = queue.pop(timeout: 2)
        rescue ThreadError
          # Ruby < 3.2 doesn't support timeout — use non_block
          event = queue.pop(true) rescue nil
        end

        if event.nil?
          # Nothing from AI yet — send keepalive to prevent Puma timeout
          yielder << ": keepalive\n\n"
          next
        end

        break if event == :done

        case event[:type]
        when "chunk"
          yielder << "data: #{JSON.generate({ type: "chunk", content: event[:content] })}\n\n"
        when "draft"
          yielder << "data: #{JSON.generate({ type: "draft", draft: event[:draft] })}\n\n"
        when "error"
          yielder << "data: #{JSON.generate({ type: "error", content: event[:content] })}\n\n"
          break
        end
      end

      yielder << "data: #{JSON.generate({ type: "done" })}\n\n"
      ai_thread.join(5) # clean up
    end

    [200, {
      "Content-Type" => "text/event-stream",
      "Cache-Control" => "no-cache",
      "X-Accel-Buffering" => "no"
    }, sse_body]
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
