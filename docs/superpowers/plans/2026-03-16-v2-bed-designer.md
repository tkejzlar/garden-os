# Bed Designer Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static `/beds` card grid with an interactive SVG canvas at `/garden` where beds can be drawn, positioned, and annotated with live plant data.
**Architecture:** Six canvas columns are added to the existing `beds` table via a new migration. A new `/garden` route serves `views/garden.erb`, which hosts a single Alpine.js component wrapping an inline SVG; all drawing, selection, drag, and resize interactions are managed in that component's state, with `PATCH /api/beds/:id/position` persisting geometry on pointer release. The existing `/beds/:id` detail page is preserved unchanged.
**Tech Stack:** Ruby/Sequel (model + routes), Alpine.js 3 (canvas state machine), inline SVG (rendering), Minitest + Rack::Test (tests)
**Spec:** `docs/superpowers/specs/2026-03-16-v2-features.md` — Section 6

---

## Step 1 — Migration: add canvas columns to beds

- [ ] Create `db/migrations/010_add_canvas_to_beds.rb`.

```ruby
# db/migrations/010_add_canvas_to_beds.rb
Sequel.migration do
  change do
    alter_table(:beds) do
      add_column :canvas_x,      Float,  null: true
      add_column :canvas_y,      Float,  null: true
      add_column :canvas_width,  Float,  null: true
      add_column :canvas_height, Float,  null: true
      add_column :canvas_points, String, text: true, null: true  # JSON [[x,y],…], null = rectangle
      add_column :canvas_color,  String, null: true              # e.g. "#86efac", null = default
    end
  end
end
```

All six columns are nullable. A bed with all canvas fields null is "unplaced" — it still functions in the data grid and on `/beds/:id`.

- [ ] Run migration against dev database:

```bash
bundle exec ruby -e "
  require_relative 'config/database'
  Sequel::Migrator.run(DB, 'db/migrations')
  puts 'Migration OK'
"
```

- [ ] Confirm the column additions:

```bash
bundle exec ruby -e "
  require_relative 'config/database'
  puts DB.schema(:beds).map { |col, _| col }.inspect
"
```

---

## Step 2 — Model update: `canvas_points_array` helper on Bed

- [ ] Edit `models/bed.rb`. Add the `canvas_points_array` getter/setter pair following the same pattern as `SuccessionPlan#varieties_list`.

```ruby
# models/bed.rb
require_relative "../config/database"
require "json"

class Bed < Sequel::Model
  one_to_many :rows

  # Returns parsed [[x,y],…] array, or [] when the bed is a rectangle / unplaced.
  def canvas_points_array
    canvas_points ? JSON.parse(canvas_points) : []
  end

  # Accepts an array of [x,y] pairs and serialises to JSON.
  def canvas_points_array=(pts)
    self.canvas_points = pts.nil? || pts.empty? ? nil : pts.to_json
  end

  # True when the bed has been placed on the canvas.
  def placed?
    !canvas_x.nil?
  end

  # True when this bed is a polygon rather than a rectangle.
  def polygon?
    !canvas_points.nil?
  end
end

class Row < Sequel::Model
  many_to_one :bed
  one_to_many :slots
end

class Slot < Sequel::Model
  many_to_one :row
  one_to_many :plants
end

class Arch < Sequel::Model; end

class IndoorStation < Sequel::Model; end
```

---

## Step 3 — API routes: position PATCH, bed POST, bed PATCH + redirect

- [ ] Edit `routes/beds.rb`. Add the three new API endpoints and the `/garden` redirect at the top, keep the existing `/beds` and `/beds/:id` routes untouched (except `/beds` now redirects to `/garden`).

Full replacement for `routes/beds.rb`:

```ruby
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
```

---

## Step 4 — Tests for new routes

- [ ] Create `test/routes/test_garden.rb`:

```ruby
# test/routes/test_garden.rb
require_relative "../test_helper"
require_relative "../../app"

class TestGarden < GardenTest

  # ── GET /garden ──────────────────────────────────────────────────────────────

  def test_garden_page_renders
    Bed.create(name: "North Bed", bed_type: "raised")
    get "/garden"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "North Bed"
  end

  def test_garden_page_empty_state
    get "/garden"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "gardenDesigner"  # Alpine component present
  end

  # ── GET /beds redirects ──────────────────────────────────────────────────────

  def test_beds_redirects_to_garden
    get "/beds"
    assert_equal 301, last_response.status
    assert_equal "http://example.org/garden", last_response.headers["Location"]
  end

  # ── POST /api/beds ───────────────────────────────────────────────────────────

  def test_create_bed_minimal
    post "/api/beds",
         { name: "South Bed" }.to_json,
         "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal "South Bed", data["name"]
    assert_nil data["canvas_x"]
  end

  def test_create_bed_with_canvas_position
    post "/api/beds",
         { name: "East Bed", canvas_x: 100.0, canvas_y: 50.0,
           canvas_width: 200.0, canvas_height: 120.0 }.to_json,
         "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status
    data = JSON.parse(last_response.body)
    assert_in_delta 100.0, data["canvas_x"]
    assert_in_delta 50.0,  data["canvas_y"]
  end

  def test_create_bed_missing_name_returns_422
    post "/api/beds",
         { bed_type: "raised" }.to_json,
         "CONTENT_TYPE" => "application/json"
    assert_equal 422, last_response.status
  end

  def test_create_bed_invalid_json_returns_400
    post "/api/beds", "not json", "CONTENT_TYPE" => "application/json"
    assert_equal 400, last_response.status
  end

  # ── PATCH /api/beds/:id/position ─────────────────────────────────────────────

  def test_patch_position_updates_canvas_fields
    bed = Bed.create(name: "West Bed", bed_type: "raised")
    patch "/api/beds/#{bed.id}/position",
          { canvas_x: 30.0, canvas_y: 40.0,
            canvas_width: 150.0, canvas_height: 80.0 }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_in_delta 30.0,  data["canvas_x"]
    assert_in_delta 40.0,  data["canvas_y"]
    assert_in_delta 150.0, data["canvas_width"]
    assert_in_delta 80.0,  data["canvas_height"]
  end

  def test_patch_position_with_polygon_points
    bed = Bed.create(name: "Odd Bed", bed_type: "raised")
    pts = [[0, 0], [100, 0], [80, 60], [20, 60]]
    patch "/api/beds/#{bed.id}/position",
          { canvas_x: 0.0, canvas_y: 0.0, canvas_points: pts }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal pts, JSON.parse(data["canvas_points"])
  end

  def test_patch_position_unknown_bed_returns_404
    patch "/api/beds/99999/position",
          { canvas_x: 0.0 }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 404, last_response.status
  end

  # ── PATCH /api/beds/:id ──────────────────────────────────────────────────────

  def test_patch_bed_updates_name
    bed = Bed.create(name: "Old Name", bed_type: "raised")
    patch "/api/beds/#{bed.id}",
          { name: "New Name" }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 200, last_response.status
    assert_equal "New Name", JSON.parse(last_response.body)["name"]
  end

  def test_patch_bed_unknown_returns_404
    patch "/api/beds/99999",
          { name: "Ghost" }.to_json,
          "CONTENT_TYPE" => "application/json"
    assert_equal 404, last_response.status
  end
end
```

- [ ] Run the new test file:

```bash
bundle exec ruby test/routes/test_garden.rb
```

All tests should pass before continuing.

- [ ] Also run the full test suite to check for regressions:

```bash
bundle exec ruby -e "Dir['test/**/*.rb'].each { |f| require_relative f }"
```

---

## Step 5 — Model unit test for `canvas_points_array`

- [ ] Create `test/models/test_bed.rb`:

```ruby
# test/models/test_bed.rb
require_relative "../test_helper"
require_relative "../../models/bed"

class TestBedModel < GardenTest

  def test_canvas_points_array_nil_when_unset
    bed = Bed.create(name: "B1", bed_type: "raised")
    assert_equal [], bed.canvas_points_array
  end

  def test_canvas_points_array_roundtrip
    pts = [[10, 20], [30, 40], [50, 10]]
    bed = Bed.create(name: "B2", bed_type: "raised")
    bed.canvas_points_array = pts
    bed.save
    bed.reload
    assert_equal pts, bed.canvas_points_array
  end

  def test_placed_false_when_canvas_x_nil
    bed = Bed.create(name: "B3", bed_type: "raised")
    refute bed.placed?
  end

  def test_placed_true_when_canvas_x_set
    bed = Bed.create(name: "B4", bed_type: "raised",
                     canvas_x: 10.0, canvas_y: 20.0)
    assert bed.placed?
  end

  def test_polygon_false_for_rectangle
    bed = Bed.create(name: "B5", bed_type: "raised")
    refute bed.polygon?
  end

  def test_polygon_true_when_points_set
    bed = Bed.create(name: "B6", bed_type: "raised")
    bed.canvas_points_array = [[0, 0], [10, 0], [10, 10]]
    bed.save
    assert bed.polygon?
  end
end
```

- [ ] Run model tests:

```bash
bundle exec ruby test/models/test_bed.rb
```

---

## Step 6 — `GET /garden` route + `views/garden.erb`

The `/garden` route is already wired in Step 3. This step creates the view.

- [ ] Create `views/garden.erb`. The view is a single Alpine.js component (`x-data="gardenDesigner()"`) wrapping an inline SVG canvas. Below the SVG sits a properties panel that slides into view when a bed is selected.

```erb
<%# views/garden.erb %>
<%
  # Serialise beds + plant data to JSON for Alpine bootstrap
  beds_json = @bed_data.map do |bd|
    bed = bd[:bed]
    {
      id:             bed.id,
      name:           bed.name,
      bed_type:       bed.bed_type,
      canvas_x:       bed.canvas_x,
      canvas_y:       bed.canvas_y,
      canvas_width:   bed.canvas_width,
      canvas_height:  bed.canvas_height,
      canvas_points:  bed.canvas_points_array,
      canvas_color:   bed.canvas_color,
      rows:           bd[:rows].map do |rd|
        {
          id:    rd[:row].id,
          name:  rd[:row].name,
          slots: rd[:slots].map do |sd|
            plant = sd[:plant]
            {
              id:   sd[:slot].id,
              name: sd[:slot].name,
              plant: plant ? {
                id:           plant.id,
                variety_name: plant.variety_name,
                crop_type:    plant.crop_type
              } : nil
            }
          end
        }
      end
    }
  end.to_json
%>

<!-- Page header -->
<div class="mb-4 flex items-center justify-between">
  <h1 class="text-2xl font-bold" style="color: var(--text-primary); letter-spacing: -0.5px;">Garden</h1>
  <a href="/beds" class="text-xs" style="color: var(--gray-500);">List view →</a>
</div>

<!-- Alpine.js Garden Designer -->
<div
  x-data="gardenDesigner(<%= beds_json.gsub("</", "<\\/") %>)"
  x-init="init()"
  @mousemove.window="onMouseMove($event)"
  @mouseup.window="onMouseUp($event)"
  @touchmove.window.prevent="onTouchMove($event)"
  @touchend.window="onTouchEnd($event)"
  style="position: relative;"
>

  <!-- Toolbar -->
  <div class="flex items-center gap-2 mb-3 flex-wrap">
    <!-- Tool buttons -->
    <div class="flex gap-1 p-1 rounded-lg" style="background: white; box-shadow: var(--card-shadow);">
      <template x-for="tool in tools" :key="tool.id">
        <button
          @click="activeTool = tool.id"
          :title="tool.label"
          class="flex items-center gap-1 px-2 py-1.5 rounded-md text-xs font-medium transition"
          :style="activeTool === tool.id
            ? 'background: var(--green-900); color: white;'
            : 'color: var(--text-secondary);'"
        >
          <span x-html="tool.icon" style="width:16px;height:16px;display:flex;align-items:center;justify-content:center;"></span>
          <span x-text="tool.label"></span>
        </button>
      </template>
    </div>

    <!-- Zoom controls -->
    <div class="flex gap-1 p-1 rounded-lg" style="background: white; box-shadow: var(--card-shadow);">
      <button @click="zoom = Math.max(0.25, zoom - 0.25)" class="px-2 py-1.5 text-xs font-bold" style="color: var(--text-secondary);">−</button>
      <span class="px-1 py-1.5 text-xs" style="color: var(--text-secondary);" x-text="Math.round(zoom * 100) + '%'"></span>
      <button @click="zoom = Math.min(4, zoom + 0.25)" class="px-2 py-1.5 text-xs font-bold" style="color: var(--text-secondary);">+</button>
    </div>

    <!-- Plant overlay toggle -->
    <button
      @click="showPlants = !showPlants"
      class="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium transition"
      style="box-shadow: var(--card-shadow);"
      :style="showPlants
        ? 'background: #d1fae5; color: #065f46;'
        : 'background: white; color: var(--text-secondary);'"
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10z"/><path d="M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12"/>
      </svg>
      Plants
    </button>

    <!-- Add bed button (rectangle shortcut) -->
    <button
      @click="activeTool = 'rect'"
      class="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium"
      style="background: var(--green-900); color: white; box-shadow: var(--card-shadow);"
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
      Add Bed
    </button>
  </div>

  <!-- SVG Canvas -->
  <div
    style="border-radius: var(--card-radius); overflow: hidden; box-shadow: var(--card-shadow); background: #f8faf5; cursor: crosshair; touch-action: none;"
    :style="activeTool === 'select' ? 'cursor: default;' : 'cursor: crosshair;'"
  >
    <svg
      id="garden-canvas"
      :width="canvasW"
      :height="canvasH"
      style="display: block; width: 100%;"
      :viewBox="`${panX} ${panY} ${canvasW / zoom} ${canvasH / zoom}`"
      @mousedown="onSvgMouseDown($event)"
      @touchstart.prevent="onSvgTouchStart($event)"
      @dblclick="onSvgDblClick($event)"
    >
      <!-- Grid -->
      <defs>
        <pattern id="smallGrid" :width="gridSize" :height="gridSize" patternUnits="userSpaceOnUse">
          <path :d="`M ${gridSize} 0 L 0 0 0 ${gridSize}`" fill="none" stroke="#d1e8d0" stroke-width="0.5"/>
        </pattern>
        <pattern id="grid" :width="gridSize * 5" :height="gridSize * 5" patternUnits="userSpaceOnUse">
          <rect :width="gridSize * 5" :height="gridSize * 5" fill="url(#smallGrid)"/>
          <path :d="`M ${gridSize * 5} 0 L 0 0 0 ${gridSize * 5}`" fill="none" stroke="#b6d8b2" stroke-width="1"/>
        </pattern>
      </defs>
      <rect x="-5000" y="-5000" width="15000" height="15000" fill="url(#grid)"/>

      <!-- Placed beds -->
      <template x-for="bed in placedBeds" :key="bed.id">
        <g
          @mousedown.stop="onBedMouseDown($event, bed)"
          @touchstart.stop.prevent="onBedTouchStart($event, bed)"
          style="cursor: move;"
          :opacity="selectedBed && selectedBed.id === bed.id ? 1 : 0.9"
        >
          <!-- Rectangle bed -->
          <template x-if="!bed.canvas_points || bed.canvas_points.length === 0">
            <g>
              <rect
                :x="bed.canvas_x"
                :y="bed.canvas_y"
                :width="bed.canvas_width || 100"
                :height="bed.canvas_height || 60"
                :fill="bedFill(bed)"
                :stroke="selectedBed && selectedBed.id === bed.id ? '#365314' : '#86a878'"
                :stroke-width="selectedBed && selectedBed.id === bed.id ? 2 : 1"
                rx="3"
              />
              <!-- Plant overlay cells -->
              <template x-if="showPlants">
                <template x-for="(row, ri) in bed.rows" :key="row.id">
                  <template x-for="(sd, si) in row.slots" :key="sd.id">
                    <template x-if="sd.plant">
                      <text
                        :x="bed.canvas_x + 4 + si * 18"
                        :y="bed.canvas_y + 14 + ri * 16"
                        font-size="9"
                        :fill="cropTextColor(sd.plant.crop_type)"
                        font-family="system-ui, sans-serif"
                        font-weight="600"
                      ><tspan x-text="sd.plant.variety_name.slice(0,2)"></tspan></text>
                    </template>
                  </template>
                </template>
              </template>
              <!-- Bed label -->
              <text
                :x="bed.canvas_x + (bed.canvas_width || 100) / 2"
                :y="bed.canvas_y + (bed.canvas_height || 60) / 2 + 4"
                text-anchor="middle"
                font-size="11"
                font-family="system-ui, sans-serif"
                font-weight="600"
                fill="#1a2e05"
                style="pointer-events: none; user-select: none;"
                x-text="bed.name"
              ></text>
              <!-- Resize handle (bottom-right corner) -->
              <template x-if="selectedBed && selectedBed.id === bed.id">
                <rect
                  :x="bed.canvas_x + (bed.canvas_width || 100) - 6"
                  :y="bed.canvas_y + (bed.canvas_height || 60) - 6"
                  width="10"
                  height="10"
                  fill="#365314"
                  rx="2"
                  style="cursor: se-resize;"
                  @mousedown.stop="onResizeHandleMouseDown($event, bed)"
                  @touchstart.stop.prevent="onResizeHandleTouchStart($event, bed)"
                />
              </template>
            </g>
          </template>

          <!-- Polygon bed -->
          <template x-if="bed.canvas_points && bed.canvas_points.length > 0">
            <g>
              <polygon
                :points="bed.canvas_points.map(p => p.join(',')).join(' ')"
                :fill="bedFill(bed)"
                :stroke="selectedBed && selectedBed.id === bed.id ? '#365314' : '#86a878'"
                :stroke-width="selectedBed && selectedBed.id === bed.id ? 2 : 1"
              />
              <!-- Bed label at centroid -->
              <text
                :x="polygonCentroid(bed.canvas_points)[0]"
                :y="polygonCentroid(bed.canvas_points)[1] + 4"
                text-anchor="middle"
                font-size="11"
                font-family="system-ui, sans-serif"
                font-weight="600"
                fill="#1a2e05"
                style="pointer-events: none; user-select: none;"
                x-text="bed.name"
              ></text>
            </g>
          </template>
        </g>
      </template>

      <!-- Polygon in progress -->
      <template x-if="activeTool === 'polygon' && polyPoints.length > 0">
        <g>
          <polyline
            :points="[...polyPoints, polyPreview].filter(Boolean).map(p => p.join(',')).join(' ')"
            fill="none"
            stroke="#365314"
            stroke-width="1.5"
            stroke-dasharray="5,3"
          />
          <template x-for="(pt, i) in polyPoints" :key="i">
            <circle :cx="pt[0]" :cy="pt[1]" r="4" fill="#365314" opacity="0.7"/>
          </template>
        </g>
      </template>

      <!-- Rectangle being drawn -->
      <template x-if="activeTool === 'rect' && drawRect">
        <rect
          :x="drawRect.x"
          :y="drawRect.y"
          :width="drawRect.w"
          :height="drawRect.h"
          fill="#d1fae5"
          fill-opacity="0.6"
          stroke="#365314"
          stroke-width="1.5"
          stroke-dasharray="5,3"
          rx="3"
        />
      </template>

      <!-- Unplaced bed list reminder -->
      <template x-if="unplacedBeds.length > 0">
        <text x="20" :y="canvasH / zoom - 20" font-size="11" fill="#9ca3af" font-family="system-ui, sans-serif">
          <tspan x-text="`${unplacedBeds.length} bed(s) not yet placed — use + Add Bed or draw with Rectangle tool`"></tspan>
        </text>
      </template>
    </svg>
  </div>

  <!-- Empty state overlay (no beds at all) -->
  <template x-if="beds.length === 0">
    <div class="flex flex-col items-center justify-center py-16 gap-3" style="position: absolute; inset: 48px 0 0; pointer-events: none;">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#86a878" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">
        <rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/>
        <rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>
      </svg>
      <p class="text-sm font-medium" style="color: var(--gray-500);">Tap + Add Bed to place your first bed</p>
    </div>
  </template>

  <!-- Properties panel (slides up when a bed is selected) -->
  <div
    x-show="selectedBed !== null"
    x-transition:enter="transition ease-out duration-200"
    x-transition:enter-start="opacity-0 translate-y-4"
    x-transition:enter-end="opacity-100 translate-y-0"
    x-transition:leave="transition ease-in duration-150"
    x-transition:leave-start="opacity-100 translate-y-0"
    x-transition:leave-end="opacity-0 translate-y-4"
    class="mt-3 rounded-xl p-4"
    style="background: white; box-shadow: var(--card-shadow);"
  >
    <template x-if="selectedBed">
      <div>
        <!-- Panel header -->
        <div class="flex items-center justify-between mb-3">
          <p class="text-xs font-semibold uppercase tracking-wide" style="color: var(--gray-500);">Selected Bed</p>
          <div class="flex gap-2">
            <a :href="'/beds/' + selectedBed.id" class="text-xs" style="color: var(--green-900);">Detail →</a>
            <button @click="selectedBed = null" class="text-xs" style="color: var(--gray-400);">✕</button>
          </div>
        </div>

        <!-- Name editor -->
        <div class="mb-3">
          <label class="text-xs font-medium block mb-1" style="color: var(--text-secondary);">Name</label>
          <input
            type="text"
            x-model="selectedBed.name"
            @change="patchBedProperty(selectedBed, 'name', selectedBed.name)"
            class="w-full rounded-lg px-3 py-1.5 text-sm border"
            style="border-color: #d1d5db; outline: none;"
          />
        </div>

        <!-- Dimensions (read from canvas) -->
        <div class="grid grid-cols-2 gap-3 mb-3">
          <div>
            <p class="text-xs font-medium mb-1" style="color: var(--text-secondary);">Width (canvas px)</p>
            <p class="text-sm font-semibold" style="color: var(--text-primary);" x-text="selectedBed.canvas_width ? Math.round(selectedBed.canvas_width) : '—'"></p>
          </div>
          <div>
            <p class="text-xs font-medium mb-1" style="color: var(--text-secondary);">Height (canvas px)</p>
            <p class="text-sm font-semibold" style="color: var(--text-primary);" x-text="selectedBed.canvas_height ? Math.round(selectedBed.canvas_height) : '—'"></p>
          </div>
        </div>

        <!-- Color picker -->
        <div class="mb-3">
          <p class="text-xs font-medium mb-2" style="color: var(--text-secondary);">Bed Color</p>
          <div class="flex gap-2 flex-wrap">
            <template x-for="color in bedColors" :key="color">
              <button
                @click="patchBedProperty(selectedBed, 'canvas_color', color); selectedBed.canvas_color = color"
                class="w-6 h-6 rounded-full border-2 transition"
                :style="`background: ${color}; border-color: ${selectedBed.canvas_color === color ? '#365314' : 'transparent'};`"
              ></button>
            </template>
            <button
              @click="patchBedProperty(selectedBed, 'canvas_color', null); selectedBed.canvas_color = null"
              class="px-2 h-6 rounded-full border text-xs"
              style="border-color: #d1d5db; color: var(--gray-500);"
            >Default</button>
          </div>
        </div>

        <!-- Rows summary + link to full editor -->
        <div>
          <p class="text-xs font-medium mb-2" style="color: var(--text-secondary);">Rows / Slots</p>
          <template x-if="selectedBed.rows && selectedBed.rows.length > 0">
            <div class="flex flex-col gap-1">
              <template x-for="row in selectedBed.rows" :key="row.id">
                <div class="flex items-center gap-2">
                  <span class="text-xs w-16 shrink-0" style="color: var(--gray-500);" x-text="row.name"></span>
                  <div class="flex gap-1 flex-wrap">
                    <template x-for="sd in row.slots" :key="sd.id">
                      <div
                        class="w-6 h-6 rounded text-center text-xs flex items-center justify-center font-medium"
                        :style="slotStyle(sd.plant)"
                        :title="sd.plant ? sd.plant.variety_name : sd.name"
                        x-text="sd.plant ? sd.plant.variety_name.slice(0,2) : ''"
                      ></div>
                    </template>
                  </div>
                </div>
              </template>
            </div>
          </template>
          <template x-if="!selectedBed.rows || selectedBed.rows.length === 0">
            <p class="text-xs" style="color: var(--gray-400);">No rows yet.</p>
          </template>
          <a :href="'/beds/' + selectedBed.id" class="inline-block mt-2 text-xs" style="color: var(--green-900);">Edit rows & slots →</a>
        </div>
      </div>
    </template>
  </div>

  <!-- New bed name modal (shown after drawing a shape) -->
  <div
    x-show="pendingShape !== null"
    x-transition
    style="position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: 100; display: flex; align-items: center; justify-content: center;"
    @click.self="pendingShape = null"
  >
    <div class="rounded-xl p-6 w-72" style="background: white; box-shadow: 0 4px 24px rgba(0,0,0,0.15);">
      <p class="font-semibold mb-3" style="color: var(--text-primary);">Name this bed</p>
      <input
        type="text"
        x-model="newBedName"
        @keydown.enter="confirmNewBed()"
        placeholder="e.g. North Bed"
        class="w-full rounded-lg px-3 py-2 text-sm border mb-3"
        style="border-color: #d1d5db; outline: none;"
        x-ref="newBedNameInput"
      />
      <div class="flex gap-2 justify-end">
        <button @click="pendingShape = null; newBedName = ''" class="px-3 py-1.5 text-sm" style="color: var(--gray-500);">Cancel</button>
        <button
          @click="confirmNewBed()"
          :disabled="!newBedName.trim()"
          class="px-4 py-1.5 text-sm font-medium rounded-lg"
          style="background: var(--green-900); color: white;"
          :style="!newBedName.trim() ? 'opacity: 0.5;' : ''"
        >Add</button>
      </div>
    </div>
  </div>

</div><!-- end x-data -->

<script>
function gardenDesigner(bedsData) {
  return {
    // ── State ────────────────────────────────────────────────────────────────
    beds:         bedsData || [],
    activeTool:   'select',   // 'select' | 'rect' | 'polygon'
    selectedBed:  null,
    showPlants:   false,
    zoom:         1,
    panX:         0,
    panY:         0,
    gridSize:     20,         // px per grid cell (represents 0.5 m at default scale)
    canvasW:      800,
    canvasH:      500,

    // Rectangle drawing state
    drawRect:     null,       // { startX, startY, x, y, w, h }

    // Polygon drawing state
    polyPoints:   [],
    polyPreview:  null,

    // Drag / resize state
    dragging:     null,       // { bed, startMouseX, startMouseY, startBedX, startBedY }
    resizing:     null,       // { bed, startMouseX, startMouseY, startW, startH }

    // New bed creation flow
    pendingShape: null,       // { type: 'rect'|'polygon', ...geometry }
    newBedName:   '',

    bedColors: [
      '#d1fae5', '#dcfce7', '#fef9c3', '#fce7f3',
      '#fee2e2', '#ffedd5', '#ede9fe', '#dbeafe'
    ],

    cropColors: {
      tomato:   { bg: '#fee2e2', text: '#991b1b' },
      pepper:   { bg: '#ffedd5', text: '#9a3412' },
      cucumber: { bg: '#dcfce7', text: '#166534' },
      herb:     { bg: '#d1fae5', text: '#065f46' },
      flower:   { bg: '#fce7f3', text: '#9d174d' },
      lettuce:  { bg: '#fef9c3', text: '#713f12' },
      squash:   { bg: '#fef3c7', text: '#92400e' },
      brassica: { bg: '#ede9fe', text: '#4c1d95' },
    },

    tools: [
      { id: 'select',  label: 'Select',    icon: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 3l14 9-7 1-3 7z"/></svg>' },
      { id: 'rect',    label: 'Rectangle', icon: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/></svg>' },
      { id: 'polygon', label: 'Polygon',   icon: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 22 19 2 19"/></svg>' },
    ],

    // ── Init ─────────────────────────────────────────────────────────────────
    init() {
      this.$nextTick(() => {
        const svg = document.getElementById('garden-canvas');
        if (svg) {
          this.canvasW = svg.parentElement.clientWidth || 800;
        }
      });
    },

    // ── Computed helpers ─────────────────────────────────────────────────────
    get placedBeds() {
      return this.beds.filter(b => b.canvas_x !== null && b.canvas_x !== undefined);
    },

    get unplacedBeds() {
      return this.beds.filter(b => b.canvas_x === null || b.canvas_x === undefined);
    },

    bedFill(bed) {
      if (bed.canvas_color) return bed.canvas_color;
      return '#e8f5e3';
    },

    cropTextColor(cropType) {
      return (this.cropColors[cropType] || { text: '#374151' }).text;
    },

    slotStyle(plant) {
      if (!plant) return 'background: #f9fafb; border: 1px solid #e5e7eb; color: #9ca3af;';
      const c = this.cropColors[plant.crop_type] || { bg: '#f3f4f6', text: '#374151' };
      return `background: ${c.bg}; color: ${c.text}; border: 1px solid ${c.bg};`;
    },

    polygonCentroid(pts) {
      if (!pts || pts.length === 0) return [0, 0];
      const x = pts.reduce((s, p) => s + p[0], 0) / pts.length;
      const y = pts.reduce((s, p) => s + p[1], 0) / pts.length;
      return [x, y];
    },

    // Convert a DOM mouse/touch event to SVG coordinate space (accounts for zoom + pan)
    svgPoint(event) {
      const svg = document.getElementById('garden-canvas');
      const rect = svg.getBoundingClientRect();
      const clientX = event.touches ? event.touches[0].clientX : event.clientX;
      const clientY = event.touches ? event.touches[0].clientY : event.clientY;
      const scaleX = (this.canvasW / this.zoom) / rect.width;
      const scaleY = (this.canvasH / this.zoom) / rect.height;
      return [
        this.panX + (clientX - rect.left) * scaleX,
        this.panY + (clientY - rect.top)  * scaleY
      ];
    },

    snap(v) {
      return Math.round(v / this.gridSize) * this.gridSize;
    },

    // ── SVG canvas events ────────────────────────────────────────────────────
    onSvgMouseDown(e) {
      if (this.activeTool === 'rect') {
        const [x, y] = this.svgPoint(e);
        this.drawRect = { startX: this.snap(x), startY: this.snap(y), x: this.snap(x), y: this.snap(y), w: 0, h: 0 };
      } else if (this.activeTool === 'polygon') {
        const [x, y] = this.svgPoint(e);
        this.polyPoints.push([this.snap(x), this.snap(y)]);
      } else if (this.activeTool === 'select') {
        this.selectedBed = null;
      }
    },

    onSvgTouchStart(e) {
      this.onSvgMouseDown(e);
    },

    onSvgDblClick(e) {
      if (this.activeTool === 'polygon' && this.polyPoints.length >= 3) {
        this.pendingShape = { type: 'polygon', points: [...this.polyPoints] };
        this.polyPoints = [];
        this.polyPreview = null;
        this.$nextTick(() => this.$refs.newBedNameInput && this.$refs.newBedNameInput.focus());
      }
    },

    onMouseMove(e) {
      this._handleMove(e);
    },

    onTouchMove(e) {
      this._handleMove(e);
    },

    _handleMove(e) {
      if (this.drawRect) {
        const [x, y] = this.svgPoint(e);
        const sx = this.drawRect.startX, sy = this.drawRect.startY;
        const ex = this.snap(x), ey = this.snap(y);
        this.drawRect = {
          startX: sx, startY: sy,
          x: Math.min(sx, ex), y: Math.min(sy, ey),
          w: Math.abs(ex - sx), h: Math.abs(ey - sy)
        };
      } else if (this.dragging) {
        const [mx, my] = this.svgPoint(e);
        const dx = mx - this.dragging.startMouseX;
        const dy = my - this.dragging.startMouseY;
        this.dragging.bed.canvas_x = this.snap(this.dragging.startBedX + dx);
        this.dragging.bed.canvas_y = this.snap(this.dragging.startBedY + dy);
      } else if (this.resizing) {
        const [mx, my] = this.svgPoint(e);
        const dw = mx - this.resizing.startMouseX;
        const dh = my - this.resizing.startMouseY;
        this.resizing.bed.canvas_width  = Math.max(this.gridSize, this.snap(this.resizing.startW + dw));
        this.resizing.bed.canvas_height = Math.max(this.gridSize, this.snap(this.resizing.startH + dh));
      } else if (this.activeTool === 'polygon' && this.polyPoints.length > 0) {
        const [x, y] = this.svgPoint(e);
        this.polyPreview = [this.snap(x), this.snap(y)];
      }
    },

    onMouseUp(e) {
      this._handleUp(e);
    },

    onTouchEnd(e) {
      this._handleUp(e);
    },

    _handleUp(e) {
      if (this.drawRect && this.drawRect.w >= this.gridSize && this.drawRect.h >= this.gridSize) {
        this.pendingShape = {
          type: 'rect',
          canvas_x: this.drawRect.x, canvas_y: this.drawRect.y,
          canvas_width: this.drawRect.w, canvas_height: this.drawRect.h
        };
        this.$nextTick(() => this.$refs.newBedNameInput && this.$refs.newBedNameInput.focus());
      }
      this.drawRect = null;

      if (this.dragging) {
        const bed = this.dragging.bed;
        this.patchPosition(bed);
        this.dragging = null;
      }

      if (this.resizing) {
        const bed = this.resizing.bed;
        this.patchPosition(bed);
        this.resizing = null;
      }
    },

    // ── Bed interaction events ────────────────────────────────────────────────
    onBedMouseDown(e, bed) {
      if (this.activeTool !== 'select') return;
      this.selectedBed = bed;
      const [mx, my] = this.svgPoint(e);
      this.dragging = {
        bed,
        startMouseX: mx, startMouseY: my,
        startBedX: bed.canvas_x, startBedY: bed.canvas_y
      };
    },

    onBedTouchStart(e, bed) {
      this.onBedMouseDown(e, bed);
    },

    onResizeHandleMouseDown(e, bed) {
      const [mx, my] = this.svgPoint(e);
      this.resizing = {
        bed,
        startMouseX: mx, startMouseY: my,
        startW: bed.canvas_width || 100,
        startH: bed.canvas_height || 60
      };
    },

    onResizeHandleTouchStart(e, bed) {
      this.onResizeHandleMouseDown(e, bed);
    },

    // ── New bed creation ──────────────────────────────────────────────────────
    confirmNewBed() {
      const name = this.newBedName.trim();
      if (!name || !this.pendingShape) return;

      const payload = { name, bed_type: 'raised', ...this.pendingShape };
      if (payload.type === 'polygon') {
        payload.canvas_points = payload.points;
        delete payload.points;
      }
      delete payload.type;

      fetch('/api/beds', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
      .then(r => r.json())
      .then(newBed => {
        newBed.rows = [];
        this.beds.push(newBed);
        this.selectedBed = newBed;
      })
      .catch(err => console.error('Failed to create bed:', err));

      this.pendingShape = null;
      this.newBedName = '';
    },

    // ── API helpers ───────────────────────────────────────────────────────────
    patchPosition(bed) {
      const payload = {
        canvas_x:      bed.canvas_x,
        canvas_y:      bed.canvas_y,
        canvas_width:  bed.canvas_width,
        canvas_height: bed.canvas_height,
      };
      if (bed.canvas_points && bed.canvas_points.length > 0) {
        payload.canvas_points = bed.canvas_points;
      }
      fetch(`/api/beds/${bed.id}/position`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      }).catch(err => console.error('Failed to save position:', err));
    },

    patchBedProperty(bed, key, value) {
      const payload = { [key]: value };
      fetch(`/api/beds/${bed.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      }).catch(err => console.error('Failed to update bed:', err));
    }
  };
}
</script>
```

---

## Step 7 — Nav update in `views/layout.erb`

The layout has four changes:
1. The `/beds` tab href becomes `/garden`.
2. The active-state check changes from `p.start_with?("/beds")` to `p.start_with?("/garden") || p.start_with?("/beds")` (so `/beds/:id` detail pages still highlight the tab).
3. The label changes from "Beds" to "Garden".
4. The icon changes from the 4-squares grid to a Lucide `map` icon.

- [ ] Edit `views/layout.erb`:

```erb
<%# Replace the existing beds tab-item block %>
    <%
      p = request.path_info
      home_active       = (p == "/")
      plants_active     = p.start_with?("/plants")
      garden_active     = p.start_with?("/garden") || p.start_with?("/beds")
      succession_active = p.start_with?("/succession")
    %>
```

And replace the beds `<a>` tag:

```erb
    <a href="/garden" class="tab-item<%= ' active' if garden_active %>">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <polygon points="3 6 9 3 15 6 21 3 21 18 15 21 9 18 3 21"/>
        <line x1="9" y1="3" x2="9" y2="18"/>
        <line x1="15" y1="6" x2="15" y2="21"/>
      </svg>
      Garden
    </a>
```

Full updated `<nav>` block for copy-paste clarity:

```erb
  <nav class="tab-bar">
    <%
      p = request.path_info
      home_active       = (p == "/")
      plants_active     = p.start_with?("/plants")
      garden_active     = p.start_with?("/garden") || p.start_with?("/beds")
      succession_active = p.start_with?("/succession")
    %>
    <a href="/" class="tab-item<%= ' active' if home_active %>">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>
      </svg>
      Home
    </a>
    <a href="/plants" class="tab-item<%= ' active' if plants_active %>">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10z"/><path d="M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12"/>
      </svg>
      Plants
    </a>
    <a href="/garden" class="tab-item<%= ' active' if garden_active %>">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <polygon points="3 6 9 3 15 6 21 3 21 18 15 21 9 18 3 21"/>
        <line x1="9" y1="3" x2="9" y2="18"/>
        <line x1="15" y1="6" x2="15" y2="21"/>
      </svg>
      Garden
    </a>
    <a href="/succession" class="tab-item<%= ' active' if succession_active %>">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/>
      </svg>
      Succession
    </a>
  </nav>
```

---

## Step 8 — Full test suite green check

- [ ] Run the complete test suite:

```bash
bundle exec ruby -e "
  Dir['test/**/*.rb'].sort.each { |f| require File.expand_path(f) }
"
```

Expected: all existing tests pass. New tests pass. The `test_beds_index` test in `test/routes/test_beds.rb` now gets a 301 response — update it to follow redirects or assert 301:

- [ ] Update `test/routes/test_beds.rb` to handle the redirect:

```ruby
# In TestBeds#test_beds_index — replace the existing assertion
def test_beds_index_redirects_to_garden
  Bed.create(name: "BB1", bed_type: "raised")
  get "/beds"
  assert_equal 301, last_response.status
  assert_includes last_response.headers["Location"], "/garden"
end
```

The other two tests (`test_bed_show_with_plants`, `test_beds_api`) are unaffected.

- [ ] Re-run tests after that fix:

```bash
bundle exec ruby test/routes/test_beds.rb
bundle exec ruby test/routes/test_garden.rb
bundle exec ruby test/models/test_bed.rb
```

---

## Step 9 — Manual smoke test

- [ ] Start the server:

```bash
bundle exec ruby app.rb
```

- [ ] Verify each behaviour:
  - [ ] `GET /beds` → browser follows redirect to `/garden`
  - [ ] `/garden` loads with SVG canvas and grid
  - [ ] Rectangle tool: click-drag on canvas → name modal appears → bed renders on canvas
  - [ ] Polygon tool: click 3+ vertices → double-click → name modal → polygon renders
  - [ ] Select tool: click a bed → properties panel slides up, name editable
  - [ ] Drag a bed → releases → position persists on page reload
  - [ ] Resize handle on a rect bed → releases → size persists on page reload
  - [ ] "Plants" toggle → crop abbreviations appear inside placed beds
  - [ ] Nav "Garden" tab highlighted when on `/garden`
  - [ ] Nav "Garden" tab still highlighted when on `/beds/:id`
  - [ ] "Detail →" link in properties panel navigates to `/beds/:id`

---

## Step 10 — Commit

- [ ] Stage and commit:

```bash
git add \
  db/migrations/010_add_canvas_to_beds.rb \
  models/bed.rb \
  routes/beds.rb \
  views/garden.erb \
  views/layout.erb \
  test/routes/test_garden.rb \
  test/routes/test_beds.rb \
  test/models/test_bed.rb

git commit -m "feat: add Bed Designer — SVG canvas at /garden with draw, drag, resize, plant overlay"
```

---

## Architecture notes for the Alpine.js component

The entire canvas state machine lives in the `gardenDesigner()` function returned to `x-data`. Key design decisions:

**Coordinate system.** All coordinates stored in the DB are SVG canvas units (pixels at zoom=1). The `viewBox` shifts with `panX`/`panY` and scales with `zoom`, so the underlying data never changes during pan/zoom — only the viewport transforms.

**Grid snapping.** `snap(v)` rounds to the nearest `gridSize` unit. Called on every pointer event that produces a coordinate. Default `gridSize = 20` means the coarsest snap; change to `gridSize = 10` for finer control.

**Drag vs. resize disambiguation.** Drag is initiated by `@mousedown` on the bed `<g>` element. Resize is initiated by `@mousedown` on the handle `<rect>`. Both use `.stop` to prevent SVG canvas from also firing `onSvgMouseDown`. The global `@mousemove.window` and `@mouseup.window` handle both, checking which state variable is non-null.

**Polygon close.** Close is triggered by double-click on the SVG canvas (`@dblclick`). A single-pixel-distance proximity check to the first point is omitted for simplicity — double-click is unambiguous enough on both mouse and touch (where the `@dblclick` equivalent is two rapid taps).

**Touch support.** Every `@mousedown` handler has a paired `@touchstart` that calls the same function after extracting `event.touches[0]`. `svgPoint()` reads `event.touches` when present. `touch-action: none` on the canvas div prevents scroll interference.

**Persistence on release only.** `patchPosition` is called once in `_handleUp`, not on every `mousemove`. This avoids a flood of PATCH requests during drag.

**Unplaced beds.** Any bed with `canvas_x === null` is shown in the count hint at the bottom of the SVG. To place them, use the Rectangle tool to draw a shape and then type the existing bed's name — which creates a duplicate. The correct flow for pre-existing unplaced beds is to select them from the list view (`/beds`) or add canvas coords directly. A future iteration could add a "Place existing bed" drag-from-list mechanic; that is out of scope for this plan.
