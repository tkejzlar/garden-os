require_relative "../models/plant"
require_relative "../models/bed"
require_relative "../models/stage_history"
require_relative "../models/harvest"
require_relative "../models/photo"

class GardenApp
  # Page routes removed — React SPA serves /plants and /plants/:id

  post "/plants/:id/advance" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant
    plant.advance_stage!(params[:stage], note: params[:note])
    redirect back
  end

  post "/plants/:id/harvests" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant

    harvest = Harvest.new(
      plant_id: plant.id,
      date:     params[:date].to_s.empty? ? Date.today : Date.parse(params[:date]),
      quantity: params[:quantity],
      notes:    params[:notes].to_s.strip.then { |n| n.empty? ? nil : n }
    )

    if harvest.valid?
      harvest.save
    else
      # Re-render show with error — simple approach consistent with existing redirect pattern
      @plant   = plant
      @history = StageHistory.where(plant_id: plant.id).order(:changed_at).all
      @harvests = Harvest.where(plant_id: plant.id).order(Sequel.desc(:date)).all
      @photos   = Photo.where(plant_id: plant.id).order(Sequel.desc(:taken_at)).all
      @harvest_error = harvest.errors.full_messages.join(", ")
      return erb :"plants/show"
    end

    redirect "/plants/#{plant.id}"
  end

  get "/api/plants/:id/harvests" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant

    harvests = Harvest.where(plant_id: plant.id).order(Sequel.desc(:date)).all.map do |h|
      {
        id:         h.id,
        date:       h.date.to_s,
        quantity:   h.quantity,
        notes:      h.notes,
        created_at: h.created_at.to_s
      }
    end

    json harvests
  end

  post "/api/plants/:id/harvests" do
    content_type :json
    plant = Plant[params[:id].to_i]
    halt 404, json(error: "Not found") unless plant

    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    harvest = Harvest.new(
      plant_id: plant.id,
      date:     body["date"].to_s.empty? ? Date.today : Date.parse(body["date"]),
      quantity: body["quantity"] || body["quantity_label"],
      notes:    body["notes"].to_s.strip.then { |n| n.empty? ? nil : n }
    )

    if harvest.valid?
      harvest.save
      status 201
      json({ id: harvest.id, date: harvest.date.to_s, quantity: harvest.quantity, notes: harvest.notes, created_at: harvest.created_at.to_s })
    else
      halt 422, json(error: harvest.errors.full_messages.join(", "))
    end
  end

  post "/plants/batch_advance" do
    ids = params[:plant_ids].split(",").map(&:to_i)
    stage = params[:stage]
    Plant.where(id: ids).all.each do |plant|
      current_idx = Plant::LIFECYCLE_STAGES.index(plant.lifecycle_stage) || -1
      new_idx = Plant::LIFECYCLE_STAGES.index(stage) || -1
      next if new_idx <= current_idx  # skip backward moves
      plant.advance_stage!(stage, note: params[:note])
    end
    redirect back
  end

  patch "/plants/:id" do
    content_type :json
    plant = Plant[params[:id].to_i]
    halt 404, json(error: "Plant not found") unless plant
    halt 403, json(error: "Not your plant") unless plant.garden_id == @current_garden.id

    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    updates = {}
    updates[:bed_id] = body["bed_id"].to_i if body["bed_id"]
    updates[:grid_x] = body["grid_x"].to_i if body["grid_x"]
    updates[:grid_y] = body["grid_y"].to_i if body["grid_y"]
    updates[:grid_w] = body["grid_w"].to_i if body["grid_w"]
    updates[:grid_h] = body["grid_h"].to_i if body["grid_h"]
    updates[:quantity] = body["quantity"].to_i if body["quantity"]
    updates[:updated_at] = Time.now if updates.any?

    if updates[:bed_id]
      bed = Bed[updates[:bed_id]]
      halt 404, json(error: "Bed not found") unless bed
      halt 403, json(error: "Not your bed") unless bed.garden_id == @current_garden.id
    end

    plant.update(updates) if updates.any?

    json plant.values
  end

  post "/api/plants" do
    data = JSON.parse(request.body.read)
    w, h = Plant.default_grid_size(data["crop_type"])
    plant = Plant.create(
      garden_id: @current_garden.id,
      bed_id: data["bed_id"]&.to_i,
      variety_name: data["variety_name"],
      crop_type: data["crop_type"].to_s.strip.downcase,
      source: data["source"],
      grid_x: data["grid_x"]&.to_i || 0,
      grid_y: data["grid_y"]&.to_i || 0,
      grid_w: data["grid_w"]&.to_i || w,
      grid_h: data["grid_h"]&.to_i || h,
      quantity: data["quantity"]&.to_i || 1,
      lifecycle_stage: data.fetch("lifecycle_stage", "seed_packet")
    )
    status 201
    json plant.values
  end

  delete "/api/plants/:id" do
    plant = Plant[params[:id].to_i]
    halt 404, json(error: "Not found") unless plant
    halt 403, json(error: "Not yours") unless plant.garden_id == @current_garden.id
    plant.destroy
    json(ok: true)
  end

  get "/api/plants" do
    json Plant.where(garden_id: @current_garden.id).exclude(lifecycle_stage: "done").all.map(&:values)
  end

  get "/api/seeds" do
    require_relative "../models/seed_packet"
    seeds = SeedPacket.where(garden_id: @current_garden.id).all.map { |s|
      { id: s.id, variety_name: s.variety_name, crop_type: s.crop_type, source: s.source }
    }
    json seeds
  end

  # ── API-prefixed duplicates (SPA) ──────────────────────────────────────

  patch "/api/plants/:id" do
    content_type :json
    plant = Plant[params[:id].to_i]
    halt 404, json(error: "Plant not found") unless plant
    halt 403, json(error: "Not your plant") unless plant.garden_id == @current_garden.id

    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    updates = {}
    updates[:bed_id] = body["bed_id"].to_i if body["bed_id"]
    updates[:grid_x] = body["grid_x"].to_i if body["grid_x"]
    updates[:grid_y] = body["grid_y"].to_i if body["grid_y"]
    updates[:grid_w] = body["grid_w"].to_i if body["grid_w"]
    updates[:grid_h] = body["grid_h"].to_i if body["grid_h"]
    updates[:quantity] = body["quantity"].to_i if body["quantity"]
    updates[:updated_at] = Time.now if updates.any?

    if updates[:bed_id]
      bed = Bed[updates[:bed_id]]
      halt 404, json(error: "Bed not found") unless bed
      halt 403, json(error: "Not your bed") unless bed.garden_id == @current_garden.id
    end

    plant.update(updates) if updates.any?

    json plant.values
  end

  post "/api/plants/:id/advance" do
    content_type :json
    plant = Plant[params[:id].to_i]
    halt 404, json(error: "Not found") unless plant

    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      { "stage" => params[:stage], "note" => params[:note] }
    end

    plant.advance_stage!(body["stage"] || params[:stage], note: body["note"] || params[:note])
    json plant.reload.values
  end

  get "/api/plants/:id" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant
    json plant.values.merge(
      days_in_stage: plant.days_in_stage,
      history: plant.stage_histories.map(&:values)
    )
  end
end
