# routes/beds.rb
require_relative "../models/bed"
require_relative "../models/plant"
require "json"

class GardenApp

  # ── Redirect ────────────────────────────────────────────────────────────────

  get "/beds" do
    redirect "/garden", 301
  end

  # ── Garden designer page ─────────────────────────────────────────────────────

  get "/garden" do
    @beds = Bed.where(garden_id: @current_garden.id).all
    @arches = Arch.where(garden_id: @current_garden.id).all
    @indoor_stations = IndoorStation.where(garden_id: @current_garden.id).all

    # Build full bed data for the plant overlay
    @bed_data = @beds.map do |bed|
      plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
      { bed: bed, plants: plants }
    end

    erb :garden
  end

  # ── Existing bed detail (preserved) ─────────────────────────────────────────

  get "/beds/:id" do
    @bed = Bed[params[:id].to_i]
    halt 404 unless @bed
    @plants = Plant.where(bed_id: @bed.id).exclude(lifecycle_stage: "done").all
    erb :"beds/show"
  end

  # ── Existing beds JSON API (preserved) ───────────────────────────────────────

  get "/api/beds" do
    beds = Bed.where(garden_id: @current_garden.id).all.map do |bed|
      active_plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
      {
        id: bed.id, name: bed.name,
        width_cm: bed.width, length_cm: bed.length,
        grid_cols: bed.grid_cols, grid_rows: bed.grid_rows,
        canvas_color: bed.canvas_color,
        canvas_x: bed.canvas_x, canvas_y: bed.canvas_y,
        canvas_width: bed.canvas_width, canvas_height: bed.canvas_height,
        canvas_points: bed.canvas_points_array,
        bed_type: bed.bed_type,
        plants: active_plants.map { |p|
          { id: p.id, variety_name: p.variety_name, crop_type: p.crop_type,
            lifecycle_stage: p.lifecycle_stage,
            grid_x: p.grid_x, grid_y: p.grid_y, grid_w: p.grid_w, grid_h: p.grid_h,
            quantity: p.quantity }
        }
      }
    end
    json beds
  end

  # ── API: reorder beds ─────────────────────────────────────────────────────────
  patch "/api/beds/reorder" do
    content_type :json
    request.body.rewind
    body = begin JSON.parse(request.body.read) rescue halt 400, json(error: "Invalid JSON") end

    ids = body["bed_ids"]
    halt 400, json(error: "bed_ids array required") unless ids.is_a?(Array)

    DB.transaction do
      ids.each_with_index do |id, i|
        Bed.where(id: id.to_i, garden_id: @current_garden.id).update(position: i)
      end
    end
    json(ok: true)
  end

  # ── API: create a new bed ────────────────────────────────────────────────────
  # POST /api/beds
  # Body (JSON): { name, bed_type?, canvas_x?, canvas_y?, canvas_width?, canvas_height?,
  #                canvas_points?, canvas_color? }

  post "/api/beds" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, json(error: "Invalid JSON")
    end

    name = body["name"].to_s.strip
    halt 422, json(error: "name is required") if name.empty?

    attrs = { name: name, garden_id: @current_garden.id }
    attrs[:bed_type]      = body["bed_type"]      if body.key?("bed_type")
    attrs[:canvas_x]      = body["canvas_x"]&.to_f
    attrs[:canvas_y]      = body["canvas_y"]&.to_f
    attrs[:canvas_width]  = body["canvas_width"]&.to_f
    attrs[:canvas_height] = body["canvas_height"]&.to_f
    attrs[:canvas_color]  = body["canvas_color"]
    attrs[:canvas_points] = body["canvas_points"].is_a?(Array) \
                              ? body["canvas_points"].to_json \
                              : body["canvas_points"]

    bed = Bed.new(attrs)
    if bed.valid? && bed.save
      status 201
      json bed.values
    else
      halt 422, json(error: bed.errors.full_messages.join(", "))
    end
  end

  # ── API: update canvas position / size ──────────────────────────────────────
  # PATCH /api/beds/:id/position
  # Body (JSON): { canvas_x, canvas_y, canvas_width?, canvas_height?, canvas_points?, canvas_color? }

  patch "/api/beds/:id/position" do
    bed = Bed[params[:id].to_i]
    halt 404, json(error: "Bed not found") unless bed

    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, json(error: "Invalid JSON")
    end

    update = {}
    update[:canvas_x]      = body["canvas_x"].to_f      if body.key?("canvas_x")
    update[:canvas_y]      = body["canvas_y"].to_f      if body.key?("canvas_y")
    if body.key?("canvas_width")
      update[:canvas_width] = body["canvas_width"].to_f
      update[:width] = body["canvas_width"].to_f.round  # sync real dimensions (cm)
    end
    if body.key?("canvas_height")
      update[:canvas_height] = body["canvas_height"].to_f
      update[:length] = body["canvas_height"].to_f.round  # sync real dimensions (cm)
    end
    update[:canvas_color]  = body["canvas_color"]       if body.key?("canvas_color")
    if body.key?("canvas_points")
      pts = body["canvas_points"]
      update[:canvas_points] = pts.is_a?(Array) ? pts.to_json : pts
    end

    bed.update(update)
    json bed.reload.values
  end

  # ── API: update bed properties ───────────────────────────────────────────────
  # PATCH /api/beds/:id
  # Body (JSON): { name?, bed_type?, orientation?, wall_type?, notes?,
  #                canvas_x?, canvas_y?, canvas_width?, canvas_height?,
  #                canvas_points?, canvas_color? }

  patch "/api/beds/:id" do
    bed = Bed[params[:id].to_i]
    halt 404, json(error: "Bed not found") unless bed

    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, json(error: "Invalid JSON")
    end

    allowed = %w[name bed_type orientation wall_type notes
                 canvas_x canvas_y canvas_width canvas_height canvas_color]
    update = body.slice(*allowed).transform_keys(&:to_sym)
    update[:canvas_x]      = update[:canvas_x].to_f      if update[:canvas_x]
    update[:canvas_y]      = update[:canvas_y].to_f      if update[:canvas_y]
    update[:canvas_width]  = update[:canvas_width].to_f  if update[:canvas_width]
    update[:canvas_height] = update[:canvas_height].to_f if update[:canvas_height]

    if body.key?("canvas_points")
      pts = body["canvas_points"]
      update[:canvas_points] = pts.is_a?(Array) ? pts.to_json : pts
    end

    bed.update(update)
    json bed.reload.values
  end

  # ── API: delete bed ──────────────────────────────────────────────────────────
  delete "/api/beds/:id" do
    bed = Bed[params[:id].to_i]
    halt 404, json(error: "Bed not found") unless bed

    bed.destroy
    json(success: true)
  end

end
