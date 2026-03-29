require_relative "../models/succession_plan"
require_relative "../models/task"

class GardenApp
  # Succession page route removed — React SPA serves /plan

  get "/api/succession/gantt" do
    today = Date.today

    plans = SuccessionPlan.where(garden_id: @current_garden.id).all.map do |sp|
      # Fetch all sow tasks whose title contains the crop name, ordered by due_date
      sow_tasks = Task
        .where(garden_id: @current_garden.id, task_type: "sow")
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

  get "/api/plan/bed-timeline" do
    content_type :json
    today = Date.today

    # Parse dates safely — SQLite may return strings
    to_date = ->(v) { v.is_a?(Date) ? v : v.is_a?(String) ? Date.parse(v) : nil rescue nil }
    earliest = to_date.call(Task.where(garden_id: @current_garden.id).min(:due_date))
    latest = to_date.call(Task.where(garden_id: @current_garden.id).max(:due_date))
    plan_starts = to_date.call(SuccessionPlan.where(garden_id: @current_garden.id).min(:season_start))
    plan_ends = to_date.call(SuccessionPlan.where(garden_id: @current_garden.id).max(:season_end))

    season_start = [earliest, plan_starts, today].compact.min - 14
    season_end = [latest, plan_ends, today + 180].compact.max + 14

    months = []
    d = Date.new(season_start.year, season_start.month, 1)
    while d <= season_end
      months << d.strftime("%Y-%m")
      d = d >> 1
    end

    beds = Bed.where(garden_id: @current_garden.id).eager(:plants).all.map do |bed|
      active_plants = bed.plants.reject { |p| p.lifecycle_stage == "done" }

      occupancy = months.map do |month_str|
        year, month = month_str.split("-").map(&:to_i)
        month_start = Date.new(year, month, 1)
        month_end = (month_start >> 1) - 1
        filled = active_plants.count do |plant|
          start_date = plant.sow_date || plant.created_at&.to_date || today
          end_date = plant.lifecycle_stage == "done" ? (plant.updated_at&.to_date || today) : season_end
          start_date <= month_end && end_date >= month_start
        end
        { month: month_str, filled: filled }
      end

      crops_grouped = active_plants.group_by(&:crop_type)

      crops = crops_grouped.map do |crop, crop_plants|
        varieties = crop_plants.map(&:variety_name).uniq
        start_date = crop_plants.map { |p| p.sow_date || p.created_at&.to_date }.compact.min
        {
          crop: crop,
          varieties: varieties,
          plant_count: crop_plants.sum(&:quantity),
          periods: [{
            start: start_date&.to_s,
            end: nil,
            status: crop_plants.any? { |p| %w[planted_out producing].include?(p.lifecycle_stage) } ? "planted" : "growing"
          }]
        }
      end

      SuccessionPlan.where(garden_id: @current_garden.id).all.each do |plan|
        next unless plan.target_beds_list.include?(bed.name)
        existing_tasks = Task.where(garden_id: @current_garden.id, task_type: "sow", status: "done")
          .where(Sequel.like(:title, "%#{plan.crop}%")).count

        (existing_tasks...plan.total_planned_sowings).each do |i|
          sow_date = plan.next_sowing_date(i)
          next unless sow_date
          crops << {
            crop: plan.crop,
            varieties: plan.varieties_list,
            plant_count: 1,
            periods: [{ start: sow_date.to_s, end: nil, status: "planned" }]
          }
        end
      end

      { bed_id: bed.id, bed_name: bed.name, grid_cols: bed.grid_cols, grid_rows: bed.grid_rows, occupancy: occupancy, crops: crops }
    end

    { today: today.to_s, season_start: season_start.to_s, season_end: season_end.to_s, beds: beds }.to_json
  end

  get "/api/succession" do
    plans = SuccessionPlan.where(garden_id: @current_garden.id).all.map do |sp|
      completed = Task.where(garden_id: @current_garden.id, task_type: "sow")
                      .where(Sequel.like(:title, "%#{sp.crop}%"))
                      .where(status: "done").count
      upcoming = Task.where(garden_id: @current_garden.id, task_type: "sow")
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

  # Succession form routes removed — React SPA handles plan creation/editing

  post "/succession/plans" do
    plan = SuccessionPlan.create(
      garden_id:             @current_garden.id,
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
      garden_id: @current_garden.id,
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

  # ── Bed Layout Endpoints ────────────────────────────────────────────────

  patch "/beds/:id/swap-plants" do
    content_type :json
    bed = Bed[params[:id].to_i]
    halt 404, json(error: "Bed not found") unless bed
    halt 403, json(error: "Not your bed") unless bed.garden_id == @current_garden.id

    request.body.rewind
    body = begin JSON.parse(request.body.read) rescue halt 400, json(error: "Invalid JSON") end

    plant_a = Plant[body["plant_a"].to_i]
    plant_b = Plant[body["plant_b"].to_i]
    halt 404, json(error: "Plant not found") unless plant_a && plant_b
    halt 422, json(error: "Plants not on this bed") unless plant_a.bed_id == bed.id && plant_b.bed_id == bed.id

    DB.transaction do
      ax, ay, aw, ah = plant_a.grid_x, plant_a.grid_y, plant_a.grid_w, plant_a.grid_h
      plant_a.update(grid_x: plant_b.grid_x, grid_y: plant_b.grid_y, grid_w: plant_b.grid_w, grid_h: plant_b.grid_h, updated_at: Time.now)
      plant_b.update(grid_x: ax, grid_y: ay, grid_w: aw, grid_h: ah, updated_at: Time.now)
    end
    json(ok: true)
  end

  post "/beds/:id/apply-layout" do
    content_type :json
    bed = Bed[params[:id].to_i]
    halt 404, json(error: "Bed not found") unless bed
    halt 403, json(error: "Not your bed") unless bed.garden_id == @current_garden.id

    request.body.rewind
    body = begin JSON.parse(request.body.read) rescue halt 400, json(error: "Invalid JSON") end

    action = body["action"]
    case action
    when "fill", "plan_full"
      suggestions = body["suggestions"] || []
      created = suggestions.map do |s|
        Plant.create(
          garden_id: @current_garden.id, bed_id: bed.id,
          variety_name: s["variety_name"], crop_type: s["crop_type"],
          grid_x: s["grid_x"]&.to_i || 0, grid_y: s["grid_y"]&.to_i || 0,
          grid_w: s["grid_w"]&.to_i || 1, grid_h: s["grid_h"]&.to_i || 1,
          quantity: s["quantity"]&.to_i || 1,
          lifecycle_stage: "seed_packet"
        )
      end
      json(ok: true, created: created.count)
    when "rearrange"
      moves = body["moves"] || []
      DB.transaction do
        moves.each do |m|
          plant = Plant[m["plant_id"].to_i]
          next unless plant && plant.garden_id == @current_garden.id && plant.bed_id == bed.id
          plant.update(grid_x: m["grid_x"]&.to_i, grid_y: m["grid_y"]&.to_i, grid_w: m["grid_w"]&.to_i || plant.grid_w, grid_h: m["grid_h"]&.to_i || plant.grid_h, updated_at: Time.now)
        end
      end
      json(ok: true)
    else
      halt 400, json(error: "Unknown action: #{action}")
    end
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
    Thread.current[:current_garden_id] = @current_garden.id
    service = PlannerService.new
    result = service.send_message(message)

    json({
      content: result[:content],
      draft: result[:draft],
      tool_calls: result[:tool_calls]
    })
  end

  # ── AI Planner: SSE streaming endpoint ──────────────────────────────────

  post "/succession/planner/ask" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    message = body["message"].to_s.strip
    halt 400, json(error: "message required") if message.empty?

    # Prepend AI drawer context if provided
    if body["context"]
      ctx = body["context"]
      parts = ["[Context: viewing #{ctx['view']} tab"]
      parts << ", bed #{ctx['bed_name']}" if ctx["bed_name"]
      parts << ", #{ctx['empty_slots']} empty slots" if ctx["empty_slots"]
      parts << ", plants: #{ctx['current_plants'].join(', ')}" if ctx["current_plants"]&.any?
      parts << "]"
      message = parts.join + " " + message
    end

    require_relative "../services/planner_service"
    require_relative "../services/garden_logger"

    garden_id = @current_garden.id

    content_type "text/event-stream"
    headers "Cache-Control" => "no-cache", "Connection" => "keep-alive"

    stream(:keep_open) do |out|
      Thread.current[:current_garden_id] = garden_id
      service = PlannerService.new

      service.send_message_streaming(message) do |event|
        break if out.closed?
        out << "data: #{JSON.generate(event)}\n\n"
      end
      out.close unless out.closed?
    end
  end

  post "/succession/planner/commit" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    # Accept either { draft_payload: {...} } or the draft object directly
    draft = body.is_a?(Hash) && body["draft_payload"].is_a?(Hash) ? body["draft_payload"] : body
    halt 400, json(error: "draft_payload required") unless draft.is_a?(Hash) && (draft["assignments"] || draft["tasks"] || draft["successions"])

    require_relative "../services/plan_committer"
    result = PlanCommitter.commit!(draft, garden_id: @current_garden.id)
    json result
  end

  delete "/succession/planner/messages" do
    require_relative "../models/planner_message"
    PlannerMessage.where(garden_id: @current_garden.id).delete
    json(success: true)
  end

  # ── API-prefixed duplicates (SPA) ──────────────────────────────────────

  post "/api/planner/ask" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    message = body["message"].to_s.strip
    halt 400, json(error: "message required") if message.empty?

    if body["context"]
      ctx = body["context"]
      parts = ["[Context: viewing #{ctx['view']} tab"]
      parts << ", bed #{ctx['bed_name']}" if ctx["bed_name"]
      parts << ", #{ctx['empty_slots']} empty slots" if ctx["empty_slots"]
      parts << ", plants: #{ctx['current_plants'].join(', ')}" if ctx["current_plants"]&.any?
      parts << "]"
      message = parts.join + " " + message
    end

    require_relative "../services/planner_service"
    require_relative "../services/garden_logger"

    garden_id = @current_garden.id

    content_type "text/event-stream"
    headers "Cache-Control" => "no-cache", "Connection" => "keep-alive"

    stream(:keep_open) do |out|
      Thread.current[:current_garden_id] = garden_id
      service = PlannerService.new

      service.send_message_streaming(message) do |event|
        break if out.closed?
        out << "data: #{JSON.generate(event)}\n\n"
      end
      out.close unless out.closed?
    end
  end

  post "/api/planner/commit" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    # Accept either { draft_payload: {...} } or the draft object directly
    draft = body.is_a?(Hash) && body["draft_payload"].is_a?(Hash) ? body["draft_payload"] : body
    halt 400, json(error: "draft_payload required") unless draft.is_a?(Hash) && (draft["assignments"] || draft["tasks"] || draft["successions"])

    require_relative "../services/plan_committer"
    result = PlanCommitter.commit!(draft, garden_id: @current_garden.id)
    json result
  end
end
