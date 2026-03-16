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
    @beds = Bed.all
    @arches = Arch.all
    @indoor_stations = IndoorStation.all

    # Build full bed data for the plant overlay (same query as the old /beds page)
    @bed_data = @beds.map do |bed|
      rows = Row.where(bed_id: bed.id).order(:position).all
      row_data = rows.map do |row|
        slots = Slot.where(row_id: row.id).order(:position).all
        slot_ids = slots.map(&:id)
        plants_by_slot = Plant.where(slot_id: slot_ids)
                              .exclude(lifecycle_stage: "done")
                              .all.group_by(&:slot_id)
        { row: row, slots: slots.map { |s| { slot: s, plant: plants_by_slot[s.id]&.first } } }
      end
      { bed: bed, rows: row_data }
    end

    erb :garden
  end

  # ── Existing bed detail (preserved) ─────────────────────────────────────────

  get "/beds/:id" do
    @bed = Bed[params[:id].to_i]
    halt 404 unless @bed
    @rows = Row.where(bed_id: @bed.id).order(:position).all
    row_ids = @rows.map(&:id)
    all_slots = Slot.where(row_id: row_ids).order(:position).all
    slot_ids = all_slots.map(&:id)
    @plants_by_slot = Plant.where(slot_id: slot_ids)
                           .exclude(lifecycle_stage: "done")
                           .all.group_by(&:slot_id)
    @slots_by_row = all_slots.group_by(&:row_id)
    erb :"beds/show"
  end

  # ── Existing beds JSON API (preserved) ───────────────────────────────────────

  get "/api/beds" do
    beds = Bed.all.map do |bed|
      rows = Row.where(bed_id: bed.id).order(:position).all.map do |row|
        slots = Slot.where(row_id: row.id).order(:position).all.map do |slot|
          plant = Plant.where(slot_id: slot.id).exclude(lifecycle_stage: "done").first
          slot.values.merge(plant: plant&.values)
        end
        row.values.merge(slots: slots)
      end
      bed.values.merge(rows: rows)
    end
    json beds
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

    attrs = { name: name }
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
    update[:canvas_width]  = body["canvas_width"].to_f  if body.key?("canvas_width")
    update[:canvas_height] = body["canvas_height"].to_f if body.key?("canvas_height")
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

end
