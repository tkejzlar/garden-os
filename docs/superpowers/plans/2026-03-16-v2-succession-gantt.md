# Succession Gantt Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the succession progress-dots page with an interactive Alpine.js + CSS Grid Gantt chart where sowing bars can be dragged to reschedule and clicked to inspect.
**Architecture:** A new `GET /api/succession/gantt` endpoint serialises every SuccessionPlan with its sow Tasks as date-range objects; the Gantt view consumes this via `fetch` on mount, renders bars with absolute CSS positioning inside a CSS Grid timeline, and sends individual `PATCH /tasks/:id/reschedule` calls on drag-release or popover "Mark done". No new database tables or migrations are needed.
**Tech Stack:** Ruby/Sinatra routes, Sequel ORM (Task + SuccessionPlan models), Alpine.js 3 (state + interactions), CSS Grid + Tailwind utility classes (layout), Minitest + Rack::Test (tests).
**Spec:** `docs/superpowers/specs/2026-03-16-v2-features.md` — Section 5

---

## Step 1 — Reschedule Route + Test

### 1a. Add `PATCH /tasks/:id/reschedule` to `routes/succession.rb`

Open `/Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os/routes/succession.rb` and append the new route inside the `GardenApp` class, after the existing `get "/api/succession"` block.

- [ ] Add the reschedule route:

```ruby
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
```

**Rules:**
- Only `due_date` is modified. `SuccessionPlan#interval_days` and `season_start` are never touched.
- Returns the updated task as JSON (200).
- 404 if task not found; 422 if date missing or unparseable.

### 1b. Test `PATCH /tasks/:id/reschedule`

Create `/Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os/test/routes/test_reschedule.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../app"

class TestReschedule < GardenTest
  def test_reschedule_updates_due_date
    task = Task.create(title: "Sow lettuce #1", task_type: "sow",
                       due_date: Date.today, status: "upcoming")
    patch "/tasks/#{task.id}/reschedule", due_date: (Date.today + 7).to_s
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal (Date.today + 7).to_s, body["due_date"]
    assert_equal (Date.today + 7), task.reload.due_date
  end

  def test_reschedule_404_for_missing_task
    patch "/tasks/99999/reschedule", due_date: Date.today.to_s
    assert_equal 404, last_response.status
  end

  def test_reschedule_422_without_date
    task = Task.create(title: "Sow lettuce #2", task_type: "sow",
                       due_date: Date.today, status: "upcoming")
    patch "/tasks/#{task.id}/reschedule"
    assert_equal 422, last_response.status
  end

  def test_reschedule_422_with_invalid_date
    task = Task.create(title: "Sow lettuce #3", task_type: "sow",
                       due_date: Date.today, status: "upcoming")
    patch "/tasks/#{task.id}/reschedule", due_date: "not-a-date"
    assert_equal 422, last_response.status
  end

  def test_reschedule_does_not_touch_succession_plan
    plan = SuccessionPlan.create(
      crop: "Basil", varieties: '["Genovese"]',
      interval_days: 14, total_planned_sowings: 4,
      season_start: Date.today, season_end: Date.today + 56,
      target_beds: '["BB2"]'
    )
    task = Task.create(title: "Sow Basil #1", task_type: "sow",
                       due_date: Date.today, status: "upcoming")
    original_interval = plan.interval_days
    patch "/tasks/#{task.id}/reschedule", due_date: (Date.today + 3).to_s
    assert_equal 200, last_response.status
    assert_equal original_interval, plan.reload.interval_days
  end
end
```

### 1c. Run tests

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && ruby test/routes/test_reschedule.rb
```

All 5 tests must pass before proceeding.

### 1d. Commit

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && \
  git add routes/succession.rb test/routes/test_reschedule.rb && \
  git commit -m "$(cat <<'EOF'
feat: add PATCH /tasks/:id/reschedule endpoint

Allows individual task due_date updates without modifying the
SuccessionPlan template — preserves plan integrity for future
task generation while enabling manual drag-to-reschedule adjustments.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Step 2 — Gantt Data Endpoint + Test

### 2a. Add `GET /api/succession/gantt` to `routes/succession.rb`

This endpoint must be placed **before** the existing `get "/api/succession"` route (Sinatra matches first-win, so the more-specific `/gantt` path must come first).

```ruby
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
```

**Shape contract** (Alpine.js relies on this):
- Top-level: `{ today: "YYYY-MM-DD", plans: [...] }`
- Each plan: `{ plan_id, crop, varieties[], target_beds[], interval_days, season_start, season_end, total_sowings, bars[] }`
- Each bar: `{ task_id, label, due_date, status, color, days_until }`

### 2b. Test `GET /api/succession/gantt`

Create `/Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os/test/routes/test_gantt_endpoint.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../app"

class TestGanttEndpoint < GardenTest
  def setup
    super
    @plan = SuccessionPlan.create(
      crop: "Spinach", varieties: '["Matador"]',
      interval_days: 14, total_planned_sowings: 3,
      season_start: Date.today, season_end: Date.today + 42,
      target_beds: '["BB3"]'
    )
  end

  def test_returns_200_with_json
    get "/api/succession/gantt"
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert body.key?("today")
    assert body.key?("plans")
  end

  def test_today_field_is_current_date
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    assert_equal Date.today.to_s, body["today"]
  end

  def test_plan_shape
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    plan = body["plans"].first
    assert_equal "Spinach", plan["crop"]
    assert_equal ["Matador"], plan["varieties"]
    assert_equal ["BB3"], plan["target_beds"]
    assert_equal 14, plan["interval_days"]
    assert plan.key?("bars")
  end

  def test_bar_color_done_is_green
    task = Task.create(title: "Sow Spinach #1", task_type: "sow",
                       due_date: Date.today - 7, status: "done")
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    bar = body["plans"].first["bars"].first
    assert_equal "green", bar["color"]
    assert_equal "done", bar["status"]
  end

  def test_bar_color_upcoming_within_7_days_is_amber
    Task.create(title: "Sow Spinach #1", task_type: "sow",
                due_date: Date.today + 3, status: "upcoming")
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    bar = body["plans"].first["bars"].first
    assert_equal "amber", bar["color"]
  end

  def test_bar_color_future_is_gray
    Task.create(title: "Sow Spinach #1", task_type: "sow",
                due_date: Date.today + 20, status: "upcoming")
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    bar = body["plans"].first["bars"].first
    assert_equal "gray", bar["color"]
  end

  def test_bar_label_is_indexed
    Task.create(title: "Sow Spinach #1", task_type: "sow",
                due_date: Date.today + 14, status: "upcoming")
    Task.create(title: "Sow Spinach #2", task_type: "sow",
                due_date: Date.today + 28, status: "upcoming")
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    bars = body["plans"].first["bars"]
    assert_equal "Sow #1", bars[0]["label"]
    assert_equal "Sow #2", bars[1]["label"]
  end

  def test_empty_plans_returns_empty_array
    SuccessionPlan.dataset.delete
    get "/api/succession/gantt"
    body = JSON.parse(last_response.body)
    assert_equal [], body["plans"]
  end
end
```

### 2c. Run tests

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && ruby test/routes/test_gantt_endpoint.rb
```

All 7 tests must pass.

### 2d. Update existing succession test

The existing `test/routes/test_succession.rb` verifies the old card-based view. Update it to confirm the new view renders and still contains the crop name (the Gantt view keeps an `x-text` label). Open the file and ensure `test_succession_shows_plan` still passes — no changes should be needed as the crop name will appear in the Alpine `x-data` JSON blob embedded in the view.

### 2e. Commit

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && \
  git add routes/succession.rb test/routes/test_gantt_endpoint.rb && \
  git commit -m "$(cat <<'EOF'
feat: add GET /api/succession/gantt endpoint

Returns all SuccessionPlans with sow task bars serialised as date
ranges with pre-computed color codes (green/amber/gray), ready for
the Alpine.js Gantt chart to consume on mount.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Step 3 — Gantt View (Alpine.js + CSS Grid)

### 3a. Replace `views/succession.erb`

Overwrite `/Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os/views/succession.erb` entirely with the following. Read the current file first (already done), then write the replacement.

**Design decisions:**
- The timeline spans `windowDays` days (default 120), starting from `startDate` (14 days before today).
- Columns are sized via a CSS custom property `--col-width` driven by Alpine `zoom` state (`dayPx`).
- Each bar is a flex div positioned with `left` and `width` computed from dates.
- The today marker is a red vertical line positioned the same way.
- Week header cells are generated in Alpine from `startDate`.
- All server interaction (initial load, reschedule PATCH, mark-done POST) goes through Alpine methods.

```erb
<%# views/succession.erb — Succession Gantt %>

<div
  x-data="gantt()"
  x-init="init()"
  class="mb-6"
>

  <!-- ── Page header ── -->
  <div class="flex items-center justify-between mb-4">
    <h1 class="text-2xl font-bold" style="color: var(--text-primary); letter-spacing: -0.5px;">
      Plan
    </h1>
    <!-- Zoom toggle -->
    <div class="flex gap-2">
      <button
        @click="setZoom('week')"
        :class="zoom === 'week' ? 'font-semibold' : 'opacity-50'"
        class="text-sm px-3 py-1 rounded-full border transition"
        style="border-color: var(--green-900); color: var(--green-900);"
      >Week</button>
      <button
        @click="setZoom('month')"
        :class="zoom === 'month' ? 'font-semibold' : 'opacity-50'"
        class="text-sm px-3 py-1 rounded-full border transition"
        style="border-color: var(--green-900); color: var(--green-900);"
      >Month</button>
    </div>
  </div>

  <!-- ── Loading / empty states ── -->
  <template x-if="loading">
    <p class="text-center py-12" style="color: var(--text-secondary);">Loading…</p>
  </template>

  <template x-if="!loading && plans.length === 0">
    <div class="text-center py-12" style="color: var(--text-secondary);">
      <p class="text-base">No succession plans set up. Create one to see the timeline.</p>
    </div>
  </template>

  <!-- ── Gantt chart ── -->
  <template x-if="!loading && plans.length > 0">
    <div>

      <!-- Outer scroll wrapper -->
      <div
        id="gantt-scroll"
        class="overflow-x-auto rounded-xl"
        style="background: white; box-shadow: var(--card-shadow);"
      >
        <!-- Inner: fixed left label column + scrolling timeline -->
        <div class="flex" style="min-width: max-content;">

          <!-- Left label column (sticky) -->
          <div
            class="flex-shrink-0 sticky left-0 z-20"
            style="width: 120px; background: white; border-right: 1px solid #e5e7eb;"
          >
            <!-- Corner spacer (aligns with header row) -->
            <div style="height: 40px; border-bottom: 1px solid #e5e7eb;"></div>
            <!-- One label per plan row -->
            <template x-for="plan in plans" :key="plan.plan_id">
              <div
                class="flex items-center px-3 text-sm font-medium truncate"
                style="height: 48px; color: var(--text-primary); border-bottom: 1px solid #f3f4f6;"
                :title="plan.crop"
                x-text="plan.crop"
              ></div>
            </template>
          </div>

          <!-- Timeline area -->
          <div class="flex-1 relative" :style="`width: ${timelineWidth}px`">

            <!-- Week/month header -->
            <div
              class="flex sticky top-0 z-10"
              style="height: 40px; border-bottom: 1px solid #e5e7eb; background: #f9faf8;"
            >
              <template x-for="seg in headerSegments" :key="seg.label + seg.left">
                <div
                  class="absolute flex items-center pl-2 text-xs font-semibold overflow-hidden whitespace-nowrap"
                  style="height: 40px; color: var(--text-secondary); border-right: 1px solid #e5e7eb;"
                  :style="`left: ${seg.left}px; width: ${seg.width}px;`"
                  x-text="seg.label"
                ></div>
              </template>
            </div>

            <!-- Today marker -->
            <div
              class="absolute top-0 bottom-0 z-30 pointer-events-none"
              style="width: 2px; background: #dc2626;"
              :style="`left: ${todayLeft}px;`"
            >
              <div
                class="absolute top-10 text-xs font-bold px-1 rounded"
                style="background: #dc2626; color: white; transform: translateX(-50%); white-space: nowrap;"
              >Today</div>
            </div>

            <!-- Plan rows -->
            <template x-for="(plan, rowIdx) in plans" :key="plan.plan_id">
              <div
                class="relative"
                style="height: 48px; border-bottom: 1px solid #f3f4f6;"
                :style="`width: ${timelineWidth}px;`"
              >
                <!-- Grid day lines (subtle) -->
                <template x-for="seg in headerSegments" :key="'line-' + seg.left">
                  <div
                    class="absolute top-0 bottom-0 pointer-events-none"
                    style="width: 1px; background: #f3f4f6;"
                    :style="`left: ${seg.left}px;`"
                  ></div>
                </template>

                <!-- Bars -->
                <template x-for="bar in plan.bars" :key="bar.task_id">
                  <div
                    class="absolute flex items-center justify-center rounded cursor-pointer select-none text-xs font-semibold text-white transition-shadow hover:shadow-md"
                    :style="barStyle(bar)"
                    :title="bar.label + ' — ' + bar.due_date"
                    @mousedown="startDrag($event, bar)"
                    @touchstart.prevent="startDrag($event, bar)"
                    @click.stop="openPopover(bar, plan)"
                  >
                    <span
                      class="truncate px-1"
                      x-text="bar.label"
                      style="pointer-events: none;"
                    ></span>
                  </div>
                </template>
              </div>
            </template>

          </div><!-- /timeline area -->
        </div><!-- /flex row -->
      </div><!-- /scroll wrapper -->

    </div>
  </template>

  <!-- ── Popover ── -->
  <template x-if="popover.open">
    <div
      class="fixed inset-0 z-50 flex items-end justify-center pb-8 px-4"
      style="background: rgba(0,0,0,0.4);"
      @click.self="closePopover()"
    >
      <div
        class="w-full max-w-sm rounded-2xl p-5 shadow-xl"
        style="background: white;"
        @click.stop
      >
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-lg font-bold" style="color: var(--text-primary);" x-text="popover.plan.crop + ' — ' + popover.bar.label"></h2>
          <button @click="closePopover()" class="text-gray-400 hover:text-gray-600 text-xl leading-none">&times;</button>
        </div>

        <dl class="text-sm space-y-1 mb-4" style="color: var(--text-secondary);">
          <div>
            <dt class="inline font-medium" style="color: var(--text-primary);">Due: </dt>
            <dd class="inline" x-text="popover.bar.due_date || '—'"></dd>
          </div>
          <div>
            <dt class="inline font-medium" style="color: var(--text-primary);">Status: </dt>
            <dd class="inline capitalize" x-text="popover.bar.status"></dd>
          </div>
          <div x-show="popover.plan.varieties.length > 0">
            <dt class="inline font-medium" style="color: var(--text-primary);">Varieties: </dt>
            <dd class="inline" x-text="popover.plan.varieties.join(', ')"></dd>
          </div>
          <div x-show="popover.plan.target_beds.length > 0">
            <dt class="inline font-medium" style="color: var(--text-primary);">Beds: </dt>
            <dd class="inline" x-text="popover.plan.target_beds.join(', ')"></dd>
          </div>
          <div x-show="popover.plan.interval_days">
            <dt class="inline font-medium" style="color: var(--text-primary);">Interval: </dt>
            <dd class="inline" x-text="'every ' + popover.plan.interval_days + ' days'"></dd>
          </div>
        </dl>

        <template x-if="popover.bar.status !== 'done'">
          <button
            @click="markDone(popover.bar)"
            :disabled="popover.saving"
            class="w-full py-2 rounded-xl text-sm font-semibold text-white transition"
            style="background: #16a34a;"
            :style="popover.saving ? 'opacity: 0.6; cursor: not-allowed;' : ''"
          >
            <span x-text="popover.saving ? 'Saving…' : 'Mark done'"></span>
          </button>
        </template>
        <template x-if="popover.bar.status === 'done'">
          <p class="text-center text-sm font-semibold" style="color: #16a34a;">Completed</p>
        </template>
      </div>
    </div>
  </template>

  <!-- Drag ghost layer (catches move/up events anywhere on page) -->
  <template x-if="drag.active">
    <div
      class="fixed inset-0 z-40 cursor-grabbing"
      style="background: transparent;"
      @mousemove.window="onDragMove($event)"
      @mouseup.window="endDrag($event)"
      @touchmove.window.prevent="onDragMove($event)"
      @touchend.window="endDrag($event)"
    ></div>
  </template>

</div>

<script>
function gantt() {
  return {
    // ── State ──────────────────────────────────────────────────────────
    loading: true,
    plans: [],
    today: null,

    zoom: 'week',      // 'week' | 'month'
    dayPx: 28,         // pixels per day (week view default)
    windowDays: 120,   // total days shown

    // Timeline window: starts 14 days before today
    startDate: null,

    drag: {
      active: false,
      bar: null,
      originX: 0,         // pageX at mousedown
      originalLeft: 0,    // bar's left px at drag start
      currentLeft: 0      // live left px during drag
    },

    popover: {
      open: false,
      bar: null,
      plan: null,
      saving: false
    },

    // ── Init ───────────────────────────────────────────────────────────
    async init() {
      this.loading = true
      try {
        const res = await fetch('/api/succession/gantt')
        const data = await res.json()
        this.today = new Date(data.today + 'T00:00:00')
        this.startDate = new Date(this.today)
        this.startDate.setDate(this.startDate.getDate() - 14)
        this.plans = data.plans
      } catch (e) {
        console.error('Gantt load failed', e)
      } finally {
        this.loading = false
      }
    },

    // ── Zoom ───────────────────────────────────────────────────────────
    setZoom(z) {
      this.zoom = z
      this.dayPx = z === 'week' ? 28 : 12
    },

    // ── Computed geometry ──────────────────────────────────────────────
    get timelineWidth() {
      return this.windowDays * this.dayPx
    },

    get todayLeft() {
      if (!this.startDate || !this.today) return 0
      return this.daysBetween(this.startDate, this.today) * this.dayPx
    },

    get headerSegments() {
      if (!this.startDate) return []
      const segs = []
      const d = new Date(this.startDate)
      const segDays = this.zoom === 'week' ? 7 : 30

      while (this.daysBetween(this.startDate, d) < this.windowDays) {
        const left = this.daysBetween(this.startDate, d) * this.dayPx
        const label = this.zoom === 'week'
          ? this.fmtDate(d, 'MMM d')
          : this.fmtDate(d, 'MMM yyyy')
        segs.push({ left, width: segDays * this.dayPx, label })
        d.setDate(d.getDate() + segDays)
      }
      return segs
    },

    // ── Bar style ──────────────────────────────────────────────────────
    barStyle(bar) {
      if (!bar.due_date || !this.startDate) return 'display: none'

      const barDate = new Date(bar.due_date + 'T00:00:00')
      const left = this.drag.active && this.drag.bar && this.drag.bar.task_id === bar.task_id
        ? this.drag.currentLeft
        : this.daysBetween(this.startDate, barDate) * this.dayPx

      const width = Math.max(this.dayPx * 2, 52)  // at least 2-day width for readability

      const bg = bar.color === 'green'  ? '#16a34a'
               : bar.color === 'amber'  ? '#d97706'
               :                          '#9ca3af'

      const top = 8
      const height = 32

      return [
        `left: ${left}px`,
        `width: ${width}px`,
        `top: ${top}px`,
        `height: ${height}px`,
        `background: ${bg}`,
        `border-radius: 6px`,
        `cursor: ${this.drag.active ? 'grabbing' : 'grab'}`,
        `user-select: none`,
        `transition: ${this.drag.active ? 'none' : 'left 0.15s ease'}`
      ].join('; ')
    },

    // ── Drag ───────────────────────────────────────────────────────────
    startDrag(event, bar) {
      const e = event.touches ? event.touches[0] : event
      const barDate = bar.due_date ? new Date(bar.due_date + 'T00:00:00') : null
      if (!barDate) return

      const originalLeft = this.daysBetween(this.startDate, barDate) * this.dayPx

      this.drag = {
        active: true,
        bar,
        originX: e.pageX,
        originalLeft,
        currentLeft: originalLeft
      }
      // prevent click from firing as a popover-open if we actually drag
      this._wasDragged = false
    },

    onDragMove(event) {
      if (!this.drag.active) return
      const e = event.touches ? event.touches[0] : event
      const delta = e.pageX - this.drag.originX
      this.drag.currentLeft = Math.max(0, this.drag.originalLeft + delta)
      if (Math.abs(delta) > 4) this._wasDragged = true
    },

    async endDrag(event) {
      if (!this.drag.active) return
      const bar = this.drag.bar
      const finalLeft = this.drag.currentLeft
      this.drag.active = false

      if (!this._wasDragged) return  // was a click, not a drag

      // Calculate new date from pixel offset
      const daysOffset = Math.round(finalLeft / this.dayPx)
      const newDate = new Date(this.startDate)
      newDate.setDate(newDate.getDate() + daysOffset)
      const newDateStr = this.toISODate(newDate)

      // Optimistic update
      const originalDate = bar.due_date
      bar.due_date = newDateStr

      try {
        const res = await fetch(`/tasks/${bar.task_id}/reschedule`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: `due_date=${encodeURIComponent(newDateStr)}`
        })
        if (!res.ok) {
          bar.due_date = originalDate  // rollback
          console.error('Reschedule failed', res.status)
        } else {
          // Recalculate color
          const daysUntil = this.daysBetween(this.today, newDate)
          bar.days_until = daysUntil
          bar.color = daysUntil <= 0 && bar.status === 'done' ? 'green'
                    : bar.status === 'done'                   ? 'green'
                    : daysUntil <= 7                          ? 'amber'
                    :                                           'gray'
        }
      } catch (e) {
        bar.due_date = originalDate
        console.error('Reschedule error', e)
      }
    },

    // ── Popover ────────────────────────────────────────────────────────
    openPopover(bar, plan) {
      if (this._wasDragged) return  // suppress if we just dragged
      this.popover = { open: true, bar, plan, saving: false }
    },

    closePopover() {
      this.popover = { open: false, bar: null, plan: null, saving: false }
    },

    async markDone(bar) {
      this.popover.saving = true
      try {
        const res = await fetch(`/tasks/${bar.task_id}/complete`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: ''
        })
        if (res.ok || res.status === 302) {
          bar.status = 'done'
          bar.color = 'green'
          this.popover.bar = { ...bar }  // force reactivity
        }
      } catch (e) {
        console.error('Mark done error', e)
      } finally {
        this.popover.saving = false
      }
    },

    // ── Helpers ────────────────────────────────────────────────────────
    daysBetween(a, b) {
      const msPerDay = 86400000
      const aUTC = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())
      const bUTC = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate())
      return Math.round((bUTC - aUTC) / msPerDay)
    },

    toISODate(d) {
      const y = d.getFullYear()
      const m = String(d.getMonth() + 1).padStart(2, '0')
      const day = String(d.getDate()).padStart(2, '0')
      return `${y}-${m}-${day}`
    },

    fmtDate(d, fmt) {
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
      if (fmt === 'MMM d')    return `${months[d.getMonth()]} ${d.getDate()}`
      if (fmt === 'MMM yyyy') return `${months[d.getMonth()]} ${d.getFullYear()}`
      return d.toDateString()
    }
  }
}
</script>
```

### 3b. Manual smoke-test checklist

After writing the file, start the app and open `/succession` in a browser:

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && ruby app.rb
```

- [ ] Page loads without JS errors in console.
- [ ] Week/month zoom toggle changes bar spacing.
- [ ] Today marker (red line) appears at correct position.
- [ ] Header labels (e.g. "Mar 16") appear above the timeline.
- [ ] Each plan row shows its crop name on the left and bars in the timeline.
- [ ] Horizontal scroll works on mobile-width viewport (DevTools).

### 3c. Update existing succession route test

Open `/Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os/test/routes/test_succession.rb`. The `test_succession_shows_plan` assertion checks for `"Lettuce"` in the response body. The new view does not server-render crop names into HTML — they are rendered client-side by Alpine. Update the test to check that the Gantt scaffold renders and the API endpoint provides the data:

```ruby
require_relative "../test_helper"
require_relative "../../app"

class TestSuccession < GardenTest
  def test_succession_index
    get "/succession"
    assert_equal 200, last_response.status
  end

  def test_succession_page_includes_alpine_component
    get "/succession"
    assert_includes last_response.body, "x-data=\"gantt()\""
  end

  def test_succession_api_still_works
    SuccessionPlan.create(crop: "Lettuce", varieties: '["Tre Colori"]',
                          interval_days: 18, total_planned_sowings: 8,
                          season_start: Date.today, season_end: Date.today + 90,
                          target_beds: '["BB1"]')
    get "/api/succession"
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal "Lettuce", body.first["crop"]
  end
end
```

### 3d. Run all tests

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && ruby -Itest test/routes/test_succession.rb && ruby -Itest test/routes/test_gantt_endpoint.rb && ruby -Itest test/routes/test_reschedule.rb
```

### 3e. Commit

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && \
  git add views/succession.erb test/routes/test_succession.rb && \
  git commit -m "$(cat <<'EOF'
feat: replace succession page with Alpine.js + CSS Grid Gantt chart

Interactive timeline with per-crop rows, color-coded sowing bars
(green/amber/gray), today marker, and week/month zoom toggle.
Loads data from /api/succession/gantt on mount.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Step 4 — Drag to Reschedule

Drag interaction is fully implemented inside the `gantt()` Alpine component written in Step 3 (`startDrag`, `onDragMove`, `endDrag` methods, plus the transparent overlay `<div>` that captures global pointer events during a drag). No additional code changes are needed — this step is a verification and polish pass.

### 4a. Verify drag behaviour manually

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && ruby app.rb
```

- [ ] Grab a bar with the mouse; it follows the cursor horizontally.
- [ ] On release, a `PATCH /tasks/:id/reschedule` request fires (check Network tab).
- [ ] Bar stays at new position; server returns 200.
- [ ] If the server returns an error, the bar snaps back to its original position.
- [ ] Touch drag works in DevTools mobile emulation (uses `event.touches[0]`).
- [ ] A pure click (no horizontal movement >4px) does NOT fire the PATCH; it opens the popover instead.

### 4b. Edge-case handling audit

Review the `endDrag` method in `views/succession.erb` and confirm:

- `Math.max(0, ...)` prevents dragging a bar before the start of the window.
- `this._wasDragged = false` is reset on `startDrag` so consecutive click/drag events are independent.
- `bar.due_date = originalDate` rollback fires on any non-2xx response.

No additional code edits needed if all checks pass. If any edge case is found, edit `views/succession.erb` to fix it and re-run Step 3d tests.

---

## Step 5 — Click to Edit (Popover)

The popover is fully implemented in the `gantt()` Alpine component written in Step 3 (`openPopover`, `closePopover`, `markDone` methods and the popover template). This step verifies correct behaviour and adds a dedicated test for the `markDone` flow.

### 5a. Verify popover manually

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && ruby app.rb
```

- [ ] Clicking a bar (without dragging) opens the popover overlay.
- [ ] Popover shows: crop + sowing label, due date, status, varieties, target beds, interval.
- [ ] "Mark done" button is visible for non-done bars; replaced by "Completed" text for done bars.
- [ ] Tapping "Mark done" calls `POST /tasks/:id/complete`, updates bar color to green, shows "Completed".
- [ ] Tapping the backdrop (`@click.self`) closes the popover.
- [ ] Tapping the `×` button closes the popover.

### 5b. Add popover/mark-done test

Append to `/Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os/test/routes/test_reschedule.rb`:

```ruby
class TestMarkDoneViaTaskRoute < GardenTest
  # The Gantt's "Mark done" button calls POST /tasks/:id/complete,
  # which is the existing task-complete route. Verify it still works.
  def test_mark_done_via_existing_complete_route
    task = Task.create(title: "Sow Tomato #1", task_type: "sow",
                       due_date: Date.today, status: "upcoming")
    post "/tasks/#{task.id}/complete"
    # Route returns 302 redirect; task should be done
    assert_includes [200, 302], last_response.status
    assert_equal "done", task.reload.status
  end
end
```

### 5c. Run tests

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && ruby -Itest test/routes/test_reschedule.rb
```

### 5d. Commit (only if any code was changed in this step)

If only tests were added:

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && \
  git add test/routes/test_reschedule.rb && \
  git commit -m "$(cat <<'EOF'
test: verify Gantt popover mark-done uses existing task complete route

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Step 6 — Rename Tab Label to "Plan"

### 6a. Edit `views/layout.erb`

Open `/Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os/views/layout.erb`.

Make two targeted edits:

**Edit 1** — Replace the Succession SVG icon with the Gantt-chart icon from the spec and update the label text:

Find:
```erb
    <a href="/succession" class="tab-item<%= ' active' if succession_active %>">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/>
      </svg>
      Succession
    </a>
```

Replace with:
```erb
    <a href="/succession" class="tab-item<%= ' active' if succession_active %>">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>
      </svg>
      Plan
    </a>
```

(The SVG is a simple horizontal-bars / list icon — a visually clear stand-in for `gantt-chart`. If `lucide` is loaded, you can also use `<i data-lucide="gantt-chart"></i>` but inline SVG is safer given the existing tab pattern.)

### 6b. Run layout-affecting tests

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && ruby -Itest test/routes/test_succession.rb && ruby -Itest test/routes/test_dashboard.rb
```

Both should pass (neither checks the tab label text).

### 6c. Verify in browser

- [ ] Bottom tab bar shows "Plan" (not "Succession") for the succession tab.
- [ ] Tab is still active/highlighted when on `/succession`.
- [ ] No layout regressions on other tabs.

### 6d. Commit

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && \
  git add views/layout.erb && \
  git commit -m "$(cat <<'EOF'
feat: rename Succession tab to Plan, update icon

Per v2 spec section 5: tab label changes from Succession to Plan
when the Gantt chart feature is shipped.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Full Test Run

After all steps are complete, run the entire test suite to confirm nothing is broken:

```bash
cd /Users/tkejzlar/Library/CloudStorage/Dropbox/scripts/garden-os && \
  ruby -Itest test/routes/test_health.rb && \
  ruby -Itest test/routes/test_dashboard.rb && \
  ruby -Itest test/routes/test_plants.rb && \
  ruby -Itest test/routes/test_beds.rb && \
  ruby -Itest test/routes/test_tasks.rb && \
  ruby -Itest test/routes/test_succession.rb && \
  ruby -Itest test/routes/test_gantt_endpoint.rb && \
  ruby -Itest test/routes/test_reschedule.rb && \
  ruby -Itest test/models/test_plant.rb && \
  ruby -Itest test/services/test_weather_service.rb && \
  ruby -Itest test/services/test_notification_service.rb && \
  ruby -Itest test/services/test_task_generator.rb && \
  ruby -Itest test/services/test_ai_advisory_service.rb
```

All tests must pass before the feature is considered done.

---

## File Change Summary

| File | Action |
|------|--------|
| `routes/succession.rb` | Add `PATCH /tasks/:id/reschedule` and `GET /api/succession/gantt` |
| `views/succession.erb` | Full replacement with Alpine.js + CSS Grid Gantt |
| `views/layout.erb` | Update tab SVG icon + label: "Succession" → "Plan" |
| `test/routes/test_reschedule.rb` | New — reschedule route + mark-done smoke tests |
| `test/routes/test_gantt_endpoint.rb` | New — gantt data endpoint tests |
| `test/routes/test_succession.rb` | Update — adapt assertions for new Alpine-rendered view |

No database migrations. No new gems. No new models.
