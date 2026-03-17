# Plan Tab Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking. **Use the frontend-design skill** for each view template task.

**Goal:** Redesign the Plan tab from a vertical scroll (chat + cards + tasks + Gantt) into a tabbed interface with summary strip, urgency-grouped tasks, bed occupancy timeline, spatial bed view, and context-aware AI drawer.

**Architecture:** Pure view-layer rewrite of `views/succession.erb` plus one new API endpoint (`/api/plan/bed-timeline`) and a minor route update for summary counts. Alpine.js manages tab state, bed expansion, timeline zoom, and AI drawer. No model changes, no migrations.

**Tech Stack:** Ruby/Sinatra, ERB, Alpine.js (CDN), Tailwind CSS (CDN), Lucide icons (CDN)

**Spec:** `docs/superpowers/specs/2026-03-17-plan-tab-redesign-design.md`

---

## File Structure

All changes are to existing files except one new helper:

```
Modified:
├── routes/succession.rb          # Add summary counts + /api/plan/bed-timeline endpoint
├── views/succession.erb          # Full rewrite — tabbed layout with 5 components
├── services/planner_service.rb   # Accept context prefix in user messages (no structural change)
├── test/routes/test_succession.rb # Update tests for new page structure + new API tests

No new files. No model changes.
```

---

## Chunk 1: Backend — Summary Counts + Bed Timeline API

### Task 1: Add Summary Counts to Succession Route

**Files:**
- Modify: `routes/succession.rb` (GET /succession route, around line 5-20)
- Modify: `test/routes/test_succession.rb`

The GET /succession route currently sets `@plans`, `@planner_messages`, `@all_tasks`, `@done_tasks`. We need to add summary counts for the strip.

- [ ] **Step 1: Write test for summary counts**

Add to `test/routes/test_succession.rb`:

```ruby
def test_succession_index_has_summary_strip
  # Create a task that's due this week
  Task.create(
    garden_id: @garden.id,
    title: "Sow lettuce",
    task_type: "sow",
    due_date: Date.today + 2,
    priority: "must",
    status: "upcoming"
  )
  # Create an overdue task
  Task.create(
    garden_id: @garden.id,
    title: "Transplant peppers",
    task_type: "transplant",
    due_date: Date.today - 3,
    priority: "should",
    status: "upcoming"
  )
  # Create a done task
  Task.create(
    garden_id: @garden.id,
    title: "Order seeds",
    task_type: "order",
    status: "done",
    completed_at: Time.now
  )

  get "/succession"
  assert_equal 200, last_response.status
  assert_includes last_response.body, "This week"
  assert_includes last_response.body, "Overdue"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb -n test_succession_index_has_summary_strip`
Expected: FAIL (page doesn't contain "This week" / "Overdue" yet)

- [ ] **Step 3: Add summary counts to route**

In `routes/succession.rb`, inside the `get "/succession"` block, after the existing instance variables, add:

```ruby
today = Date.today
week_end = today + 7

@overdue_count = Task.where(garden_id: @current_garden.id)
  .exclude(status: %w[done skipped])
  .where { due_date < today }
  .count

@due_this_week_count = Task.where(garden_id: @current_garden.id)
  .exclude(status: %w[done skipped])
  .where(due_date: today..week_end)
  .count

@done_count = Task.where(garden_id: @current_garden.id, status: "done").count
@total_task_count = Task.where(garden_id: @current_garden.id).count
@total_plants = Plant.where(garden_id: @current_garden.id).count
@succession_count = SuccessionPlan.where(garden_id: @current_garden.id).count
```

- [ ] **Step 4: Verify route doesn't break existing page**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb -n test_succession_index`
Expected: PASS — the page still renders (we added variables but the template doesn't use them yet). The `test_succession_index_has_summary_strip` test will pass after the template rewrite in Task 4.

- [ ] **Step 5: Run existing tests to ensure no regression**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb`
Expected: Existing tests pass (we only added variables, didn't change output yet).

- [ ] **Step 6: Commit**

```bash
git add routes/succession.rb test/routes/test_succession.rb
git commit -m "feat: add summary counts to succession route for plan tab redesign"
```

---

### Task 2: Add Bed Timeline API Endpoint

**Files:**
- Modify: `routes/succession.rb` (add new route)
- Modify: `test/routes/test_succession.rb`

New endpoint `GET /api/plan/bed-timeline` returns bed occupancy data.

- [ ] **Step 1: Write test for bed timeline API**

Add to `test/routes/test_succession.rb`:

```ruby
def test_bed_timeline_api
  # Create a bed with rows and slots
  bed = Bed.create(garden_id: @garden.id, name: "BB1")
  row = Row.create(bed_id: bed.id, position: 1)
  slot = Slot.create(row_id: row.id, position: 1)

  # Create a plant in the slot
  plant = Plant.create(
    garden_id: @garden.id,
    slot_id: slot.id,
    variety_name: "Raf",
    crop_type: "tomato",
    lifecycle_stage: "planted_out",
    sow_date: Date.today - 30
  )

  get "/api/plan/bed-timeline"
  assert_equal 200, last_response.status

  data = JSON.parse(last_response.body)
  assert_equal Date.today.to_s, data["today"]
  assert data["beds"].is_a?(Array)
  assert_equal 1, data["beds"].length

  bed_data = data["beds"].first
  assert_equal "BB1", bed_data["bed_name"]
  assert_equal 1, bed_data["total_slots"]
  assert bed_data["occupancy"].is_a?(Array)
  assert bed_data["crops"].is_a?(Array)
  assert_equal "Raf", bed_data["crops"].first["crop"]
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb -n test_bed_timeline_api`
Expected: FAIL — route doesn't exist yet

- [ ] **Step 3: Implement bed timeline endpoint**

Add to `routes/succession.rb`, after the existing `get "/api/succession"` block:

```ruby
get "/api/plan/bed-timeline" do
  content_type :json
  today = Date.today

  # Determine season window from tasks and plans
  earliest = Task.where(garden_id: @current_garden.id).min(:due_date)
  latest = Task.where(garden_id: @current_garden.id).max(:due_date)
  plan_starts = SuccessionPlan.where(garden_id: @current_garden.id).min(:season_start)
  plan_ends = SuccessionPlan.where(garden_id: @current_garden.id).max(:season_end)

  season_start = [earliest, plan_starts, today].compact.min - 14
  season_end = [latest, plan_ends, today + 180].compact.max + 14

  # Generate month list
  months = []
  d = Date.new(season_start.year, season_start.month, 1)
  while d <= season_end
    months << d.strftime("%Y-%m")
    d = d >> 1
  end

  beds = Bed.where(garden_id: @current_garden.id).all.map do |bed|
    rows = bed.rows
    slots = rows.flat_map(&:slots)
    total_slots = slots.count

    # Current plants in slots
    plants = slots.flat_map(&:plants).reject { |p| p.lifecycle_stage == "done" }

    # Monthly occupancy: count slots with active plants per month
    occupancy = months.map do |month_str|
      year, month = month_str.split("-").map(&:to_i)
      month_start = Date.new(year, month, 1)
      month_end = (month_start >> 1) - 1

      filled = slots.count do |slot|
        slot.plants.any? do |plant|
          start_date = plant.sow_date || plant.created_at&.to_date || today
          end_date = plant.lifecycle_stage == "done" ? (plant.updated_at&.to_date || today) : season_end
          start_date <= month_end && end_date >= month_start
        end
      end

      { month: month_str, filled: filled }
    end

    # Group plants by crop type
    crops_grouped = plants.group_by(&:crop_type)

    crops = crops_grouped.map do |crop, crop_plants|
      varieties = crop_plants.map(&:variety_name).uniq
      start_date = crop_plants.map { |p| p.sow_date || p.created_at&.to_date }.compact.min
      {
        crop: crop,
        varieties: varieties,
        plant_count: crop_plants.count,
        periods: [{
          start: start_date&.to_s,
          end: nil,
          status: crop_plants.any? { |p| %w[planted_out producing].include?(p.lifecycle_stage) } ? "planted" : "growing"
        }]
      }
    end

    # Add succession plan projections
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

    {
      bed_id: bed.id,
      bed_name: bed.name,
      total_slots: total_slots,
      occupancy: occupancy,
      crops: crops
    }
  end

  { today: today.to_s, season_start: season_start.to_s, season_end: season_end.to_s, beds: beds }.to_json
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb -n test_bed_timeline_api`
Expected: PASS

- [ ] **Step 5: Run all succession tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add routes/succession.rb test/routes/test_succession.rb
git commit -m "feat: add /api/plan/bed-timeline endpoint for occupancy heat-map"
```

---

### Task 3: Add Context Support to Planner Ask Route

**Files:**
- Modify: `routes/succession.rb` (POST /succession/planner/ask route)

The AI drawer sends context with each message. We prepend it to the user text before passing to PlannerService.

- [ ] **Step 1: Modify the planner/ask route**

In `routes/succession.rb`, find the `post "/succession/planner/ask"` block (around line 206). The route parses JSON into `body` (line 209), extracts `message = body["message"]` (line 214), then inside a `Thread.new` block calls `result = service.send_message(message)` (line 232).

Add context prepending **before** the Thread.new block, right after `message = body["message"].to_s.strip` (line 214). Replace lines 214-215 with:

```ruby
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
```

The existing `result = service.send_message(message)` on line 232 stays unchanged — it will now receive the context-prefixed message.

- [ ] **Step 2: Run all tests to verify no regression**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb`
Expected: All tests pass (this route isn't directly tested, but we verify nothing breaks)

- [ ] **Step 3: Commit**

```bash
git add routes/succession.rb
git commit -m "feat: planner/ask accepts context for AI drawer awareness"
```

---

## Chunk 2: Frontend — Template Rewrite

### Task 4: Rewrite succession.erb — Page Shell + Summary Strip + Tabs

**Files:**
- Modify: `views/succession.erb` (full rewrite)

This is the biggest task. We rewrite the entire 852-line template. The approach: replace the file with the new structure containing all 5 components.

**Important:** Use the `frontend-design` skill for this task to ensure design quality.

- [ ] **Step 1: Write the complete new template**

Replace `views/succession.erb` entirely. The new template has this structure:

```
1. Inline CSS (scoped styles for components)
2. marked.js CDN script tag (already in current template — carry forward)
3. Data injection: `<script id="planner-data" type="application/json"><%= @planner_messages.to_json %></script>`
4. Alpine.js x-data wrapper for the whole page
4. Summary strip (static ERB)
5. Tab bar (Alpine.js tab switching)
6. Tasks tab panel
7. Timeline tab panel (fetches /api/plan/bed-timeline)
8. Beds tab panel (ERB-rendered bed cards)
9. AI FAB button
10. AI drawer (slide-up panel)
11. Alpine.js component functions: planTab(), aiDrawer()
```

The full template code is too large to inline here. Key implementation notes:

**Page-level Alpine component (`planTab()`):**

```javascript
function planTab() {
  return {
    tab: 'tasks',
    expandedBeds: [],
    timelineData: null,
    loading: false,

    init() {
      // Preload timeline data
      this.fetchTimeline();
    },

    async fetchTimeline() {
      this.loading = true;
      try {
        const res = await fetch('/api/plan/bed-timeline');
        this.timelineData = await res.json();
      } catch(e) {
        console.error('Timeline fetch failed:', e);
      }
      this.loading = false;
    },

    toggleBed(bedId) {
      const idx = this.expandedBeds.indexOf(bedId);
      if (idx >= 0) this.expandedBeds.splice(idx, 1);
      else this.expandedBeds.push(bedId);
    },

    isBedExpanded(bedId) {
      return this.expandedBeds.includes(bedId);
    },

    // Heat-map color for a month cell
    occupancyColor(filled, total) {
      if (total === 0) return 'rgba(34,197,94,0.05)';
      const ratio = filled / total;
      if (ratio === 0) return 'rgba(34,197,94,0.05)';
      if (ratio < 0.5) return 'rgba(34,197,94,0.2)';
      if (ratio < 1) return 'rgba(34,197,94,0.4)';
      return 'rgba(34,197,94,0.6)';
    },

    getAIContext() {
      return { view: this.tab };
    }
  }
}
```

**Summary strip ERB:**

```erb
<div style="padding: 14px 16px 10px; background: linear-gradient(135deg, var(--green-50), var(--yellow-50));">
  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
    <div style="font-size: 16px; font-weight: 700; color: var(--green-900);">Season Plan</div>
    <div style="font-size: 11px; color: var(--text-secondary);"><%= @total_plants %> plants · <%= @succession_count %> successions</div>
  </div>
  <div style="display: flex; gap: 8px;">
    <div style="flex: 1; background: var(--card-bg); border-radius: 8px; padding: 8px; text-align: center; box-shadow: var(--card-shadow);">
      <div style="font-size: 18px; font-weight: 700; color: var(--green-900);"><%= @due_this_week_count %></div>
      <div style="font-size: 9px; color: var(--gray-400); text-transform: uppercase; letter-spacing: 0.5px;">This week</div>
    </div>
    <div style="flex: 1; background: var(--card-bg); border-radius: 8px; padding: 8px; text-align: center; box-shadow: var(--card-shadow);">
      <div style="font-size: 18px; font-weight: 700; color: <%= @overdue_count > 0 ? 'var(--warning)' : 'var(--green-900)' %>;"><%= @overdue_count %></div>
      <div style="font-size: 9px; color: var(--gray-400); text-transform: uppercase; letter-spacing: 0.5px;">Overdue</div>
    </div>
    <div style="flex: 1; background: var(--card-bg); border-radius: 8px; padding: 8px; text-align: center; box-shadow: var(--card-shadow);">
      <div style="font-size: 18px; font-weight: 700; color: var(--green-900);"><%= @done_count %><span style="font-size: 12px; color: var(--gray-400);">/<%= @total_task_count %></span></div>
      <div style="font-size: 9px; color: var(--gray-400); text-transform: uppercase; letter-spacing: 0.5px;">Done</div>
    </div>
  </div>
</div>
```

**Tab bar:**

```erb
<div style="display: flex; background: var(--card-bg); border-bottom: 1px solid #e5e7eb; padding: 0 8px;">
  <template x-for="t in ['tasks', 'timeline', 'beds']">
    <button @click="tab = t" :style="tab === t ? 'font-weight: 600; color: var(--green-900); border-bottom: 2px solid var(--green-900);' : 'color: var(--gray-400);'" style="flex: 1; padding: 10px 0; text-align: center; font-size: 12px; background: none; border: none; cursor: pointer; margin-bottom: -1px;" x-text="t.charAt(0).toUpperCase() + t.slice(1)"></button>
  </template>
</div>
```

**Tasks tab panel:** Groups tasks by urgency using ERB. Server-side grouping:

```erb
<div x-show="tab === 'tasks'" style="padding: 12px 16px;">
  <% today = Date.today; week_end = today + 7 %>
  <% overdue = @all_tasks.select { |t| t.due_date && t.due_date < today } %>
  <% this_week = @all_tasks.select { |t| t.due_date && t.due_date >= today && t.due_date <= week_end } %>
  <% later = @all_tasks.select { |t| t.due_date.nil? || t.due_date > week_end } %>

  <% if overdue.any? %>
    <div style="font-size: 10px; font-weight: 600; color: var(--warning); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 6px;">Overdue</div>
    <% overdue.each do |task| %>
      <!-- Overdue task card with red accent -->
      <div style="display: flex; align-items: center; gap: 10px; padding: 12px; background: var(--alert-red-bg); border-radius: 10px; margin-bottom: 6px; border-left: 3px solid var(--warning);">
        <button @click="fetch('/tasks/<%= task.id %>/complete', {method:'POST'}).then(() => location.reload())" style="width: 22px; height: 22px; border-radius: 50%; border: 2px solid var(--warning); background: none; cursor: pointer; flex-shrink: 0;"></button>
        <div style="flex: 1;">
          <div style="font-size: 13px; font-weight: 500; color: var(--text-primary);"><%= task.title %></div>
          <div style="font-size: 11px; color: var(--warning);">
            <%= (today - task.due_date).to_i %> days overdue
            <% if task.beds.any? %> · <%= task.beds.map(&:name).join(", ") %><% end %>
          </div>
        </div>
        <% if task.priority %>
          <div style="font-size: 10px; padding: 2px 8px; border-radius: 10px;
            <% case task.priority
               when 'must' then %>background: var(--alert-red-bg); color: var(--alert-red-text);<%
               when 'should' then %>background: var(--alert-amber-bg); color: #92400e;<%
               else %>background: #f3f4f6; color: var(--text-secondary);<% end %>
          "><%= task.priority %></div>
        <% end %>
      </div>
    <% end %>
  <% end %>

  <% if this_week.any? %>
    <div style="font-size: 10px; font-weight: 600; color: var(--green-900); text-transform: uppercase; letter-spacing: 0.5px; margin: 12px 0 6px;">This week</div>
    <% this_week.each do |task| %>
      <div style="display: flex; align-items: center; gap: 10px; padding: 12px; background: var(--card-bg); border-radius: 10px; margin-bottom: 6px; box-shadow: var(--card-shadow);">
        <button @click="fetch('/tasks/<%= task.id %>/complete', {method:'POST'}).then(() => location.reload())" style="width: 22px; height: 22px; border-radius: 50%; border: 2px solid var(--green-900); background: none; cursor: pointer; flex-shrink: 0;"></button>
        <div style="flex: 1;">
          <div style="font-size: 13px; font-weight: 500;"><%= task.title %></div>
          <div style="font-size: 11px; color: var(--text-secondary);">
            <%= task.due_date == today ? "Today" : task.due_date == today + 1 ? "Tomorrow" : task.due_date.strftime("%b %-d") %>
            <% if task.beds.any? %> · <%= task.beds.map(&:name).join(", ") %><% end %>
          </div>
        </div>
        <% if task.priority %>
          <div style="font-size: 10px; padding: 2px 8px; border-radius: 10px;
            <% case task.priority
               when 'must' then %>background: var(--alert-red-bg); color: var(--alert-red-text);<%
               when 'should' then %>background: var(--alert-amber-bg); color: #92400e;<%
               else %>background: #f3f4f6; color: var(--text-secondary);<% end %>
          "><%= task.priority %></div>
        <% end %>
      </div>
    <% end %>
  <% end %>

  <% if later.any? %>
    <div style="font-size: 10px; font-weight: 600; color: var(--gray-400); text-transform: uppercase; letter-spacing: 0.5px; margin: 12px 0 6px;">Later</div>
    <div style="opacity: 0.6;">
      <% later.each do |task| %>
        <div style="display: flex; align-items: center; gap: 10px; padding: 10px 12px; background: var(--card-bg); border-radius: 10px; margin-bottom: 4px; box-shadow: 0 1px 2px rgba(0,0,0,0.03);">
          <div style="width: 18px; height: 18px; border-radius: 50%; border: 1.5px solid #d1d5db; flex-shrink: 0;"></div>
          <div style="flex: 1;">
            <div style="font-size: 12px; color: var(--text-secondary);"><%= task.title %></div>
            <div style="font-size: 10px; color: var(--gray-400);"><%= task.due_date&.strftime("%b %-d") %></div>
          </div>
        </div>
      <% end %>
    </div>
  <% end %>

  <% if @all_tasks.empty? %>
    <div style="text-align: center; padding: 40px 20px; color: var(--text-secondary); font-size: 14px;">
      No tasks yet — use the AI planner to get started.
    </div>
  <% end %>
</div>
```

**Timeline tab panel:** Fetches data via Alpine, renders heat-map:

```erb
<div x-show="tab === 'timeline'" style="padding: 12px 0;">
  <!-- Zoom controls -->
  <div style="display: flex; justify-content: space-between; align-items: center; padding: 0 16px; margin-bottom: 10px;">
    <div style="font-size: 11px; font-weight: 600; color: var(--green-900);">Bed Occupancy</div>
    <!-- Week zoom can be added later as an enhancement -->
  </div>

  <template x-if="loading">
    <div style="text-align: center; padding: 40px; color: var(--text-secondary);">Loading timeline...</div>
  </template>

  <template x-if="!loading && timelineData">
    <div style="padding: 0 16px;">
      <!-- Month headers -->
      <div style="display: flex; margin-bottom: 6px;">
        <div style="width: 48px;"></div>
        <div style="flex: 1; display: flex;">
          <template x-for="m in timelineData.beds[0]?.occupancy || []" :key="m.month">
            <div style="flex: 1; font-size: 9px; color: var(--gray-400); text-align: center;" x-text="['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][parseInt(m.month.split('-')[1])-1]"></div>
          </template>
        </div>
      </div>

      <!-- Bed rows -->
      <template x-for="bed in timelineData.beds" :key="bed.bed_id">
        <div style="margin-bottom: 4px;">
          <!-- Collapsed heat-map bar -->
          <div style="display: flex; align-items: center; gap: 6px; cursor: pointer;" @click="toggleBed(bed.bed_id)">
            <div style="width: 42px; font-size: 11px; font-weight: 600; color: var(--green-900); text-align: right;" x-text="bed.bed_name + (isBedExpanded(bed.bed_id) ? ' ▾' : ' ▸')"></div>
            <div style="flex: 1; height: 28px; border-radius: 6px; display: flex; overflow: hidden; border: 1px solid #e5e7eb;">
              <template x-for="m in bed.occupancy" :key="m.month">
                <div style="flex: 1;" :style="'background: ' + occupancyColor(m.filled, bed.total_slots)"></div>
              </template>
            </div>
          </div>

          <!-- Expanded crop rows -->
          <template x-if="isBedExpanded(bed.bed_id)">
            <div style="background: white; border-radius: 8px; padding: 6px 8px; margin-top: 4px; border: 1px solid var(--green-900);">
              <template x-for="crop in bed.crops" :key="crop.crop">
                <div style="display: flex; align-items: center; gap: 4px; margin-bottom: 2px; padding-left: 8px;">
                  <div style="width: 50px; font-size: 9px; color: var(--text-secondary); text-align: right; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;" x-text="crop.crop"></div>
                  <div style="flex: 1; height: 12px; background: var(--green-50); border-radius: 3px; position: relative;">
                    <template x-for="(period, pi) in crop.periods" :key="pi">
                      <div :style="(() => {
                        const ss = new Date(timelineData.season_start);
                        const se = new Date(timelineData.season_end);
                        const span = se - ss;
                        const ps = period.start ? new Date(period.start) : ss;
                        const pe = period.end ? new Date(period.end) : se;
                        const left = Math.max(0, (ps - ss) / span * 100);
                        const width = Math.min(100 - left, (pe - ps) / span * 100);
                        return 'position: absolute; height: 100%; border-radius: 3px;' +
                          (period.status === 'planned' ? 'border: 1px dashed rgba(34,197,94,0.6); background: rgba(34,197,94,0.08);' : 'background: rgba(34,197,94,0.25);') +
                          'left:' + left + '%; width:' + Math.max(2, width) + '%;';
                      })()"></div>
                    </template>
                  </div>
                  <div style="font-size: 8px; color: var(--gray-400); width: 24px; text-align: right;" x-text="'×' + crop.plant_count"></div>
                </div>
              </template>
            </div>
          </template>
        </div>
      </template>

      <!-- Legend -->
      <div style="display: flex; gap: 12px; justify-content: center; margin-top: 14px;">
        <div style="display: flex; align-items: center; gap: 4px; font-size: 10px; color: var(--text-secondary);">
          <div style="width: 16px; height: 10px; background: rgba(34,197,94,0.05); border-radius: 2px; border: 1px solid #e5e7eb;"></div> Empty
        </div>
        <div style="display: flex; align-items: center; gap: 4px; font-size: 10px; color: var(--text-secondary);">
          <div style="width: 16px; height: 10px; background: rgba(34,197,94,0.4); border-radius: 2px;"></div> Partial
        </div>
        <div style="display: flex; align-items: center; gap: 4px; font-size: 10px; color: var(--text-secondary);">
          <div style="width: 16px; height: 10px; background: rgba(34,197,94,0.6); border-radius: 2px;"></div> Full
        </div>
        <div style="display: flex; align-items: center; gap: 4px; font-size: 10px; color: var(--text-secondary);">
          <div style="width: 16px; height: 10px; background: rgba(34,197,94,0.08); border-radius: 2px; border: 1px dashed rgba(34,197,94,0.6);"></div> Planned
        </div>
      </div>
    </div>
  </template>

  <template x-if="!loading && !timelineData?.beds?.length">
    <div style="text-align: center; padding: 40px 20px; color: var(--text-secondary); font-size: 14px;">
      No plantings yet — use the AI planner to get started.
    </div>
  </template>
</div>
```

**Beds tab panel:** ERB-rendered bed cards:

```erb
<div x-show="tab === 'beds'" style="padding: 12px 16px;">
  <%
    beds = Bed.where(garden_id: @current_garden.id).all
    arches = Arch.where(garden_id: @current_garden.id).all
    stations = IndoorStation.where(garden_id: @current_garden.id).all
  %>

  <% if beds.any? || arches.any? || stations.any? %>
    <!-- Occupancy summary pills -->
    <div style="display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 12px;">
      <% beds.each do |bed| %>
        <% slots = bed.rows.flat_map(&:slots); filled = slots.count { |s| s.plants.any? { |p| p.lifecycle_stage != "done" } } %>
        <div style="padding: 4px 10px; background: var(--card-bg); border-radius: 8px; font-size: 11px; box-shadow: var(--card-shadow);">
          <span style="font-weight: 600; color: var(--green-900);"><%= bed.name %></span>
          <span style="color: var(--text-secondary);"><%= filled %>/<%= slots.count %></span>
        </div>
      <% end %>
    </div>
  <% end %>

  <% if beds.any? %>
    <div style="font-size: 10px; font-weight: 600; color: var(--green-900); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 8px;">Outdoor Beds</div>
    <% beds.each do |bed| %>
      <div style="background: var(--card-bg); border-radius: var(--card-radius); padding: 12px; margin-bottom: 10px; box-shadow: var(--card-shadow);">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
          <div>
            <div style="font-size: 14px; font-weight: 600; color: var(--green-900);"><%= bed.name %></div>
            <% rows = bed.rows.sort_by(&:position); total_slots = rows.flat_map(&:slots).count %>
            <div style="font-size: 10px; color: var(--text-secondary);"><%= rows.count %> rows · <%= total_slots %> slots</div>
          </div>
          <% filled = rows.flat_map(&:slots).count { |s| s.plants.any? { |p| p.lifecycle_stage != "done" } } %>
          <div style="font-size: 12px; font-weight: 600; color: var(--green-900);"><%= filled %>/<%= total_slots %> <span style="font-weight: 400; color: var(--text-secondary);">filled</span></div>
        </div>
        <!-- Slot grid -->
        <div style="display: flex; flex-direction: column; gap: 3px;">
          <% rows.each do |row| %>
            <div style="display: flex; gap: 3px;">
              <% row.slots.sort_by(&:position).each do |slot| %>
                <% plant = slot.plants.find { |p| p.lifecycle_stage != "done" } %>
                <% if plant %>
                  <a href="/plants/<%= plant.id %>" style="flex: 1; background: <%=
                    case plant.crop_type.to_s.downcase
                    when 'tomato', 'pepper', 'eggplant' then '#fef2f2'
                    when 'lettuce', 'spinach', 'chard', 'kale' then '#f0fdf4'
                    when 'herb', 'basil' then '#ecfdf5'
                    when 'flower' then '#fefce8'
                    when 'cucumber', 'squash', 'melon', 'zucchini' then '#f0f9ff'
                    else '#f9fafb'
                    end %>; border-radius: 6px; padding: 6px 8px; text-decoration: none;">
                    <div style="font-size: 11px; font-weight: 500; color: var(--text-primary);"><%= plant.variety_name %></div>
                    <div style="font-size: 9px; color: var(--text-secondary);"><%= plant.crop_type %> · <%= plant.lifecycle_stage.tr('_', ' ') %></div>
                  </a>
                <% else %>
                  <div style="flex: 1; background: #f9fafb; border-radius: 6px; padding: 6px 8px; border: 1px dashed #d1d5db;">
                    <div style="font-size: 11px; color: var(--gray-400);">Empty</div>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
  <% end %>

  <% if arches.any? %>
    <div style="font-size: 10px; font-weight: 600; color: #8b5cf6; text-transform: uppercase; letter-spacing: 0.5px; margin: 16px 0 8px;">Arches</div>
    <% arches.each do |arch| %>
      <div style="background: var(--card-bg); border-radius: var(--card-radius); padding: 12px; margin-bottom: 8px; box-shadow: var(--card-shadow); border-left: 3px solid #8b5cf6;">
        <div style="font-size: 13px; font-weight: 600; color: var(--green-900);"><%= arch.name %></div>
        <div style="font-size: 10px; color: var(--text-secondary);">
          <%= arch.respond_to?(:between_beds) ? arch.between_beds : '' %>
        </div>
      </div>
    <% end %>
  <% end %>

  <% if stations.any? %>
    <div style="font-size: 10px; font-weight: 600; color: #f59e0b; text-transform: uppercase; letter-spacing: 0.5px; margin: 16px 0 8px;">Indoor Stations</div>
    <% stations.each do |station| %>
      <div style="background: var(--card-bg); border-radius: var(--card-radius); padding: 12px; margin-bottom: 8px; box-shadow: var(--card-shadow); border-left: 3px solid #f59e0b;">
        <div style="font-size: 13px; font-weight: 600; color: var(--green-900);"><%= station.name %></div>
        <div style="font-size: 10px; color: var(--text-secondary);"><%= station.respond_to?(:station_type) ? station.station_type : 'Indoor' %></div>
        <% indoor_plants = Plant.where(indoor_station_id: station.id).exclude(lifecycle_stage: "done").all %>
        <% if indoor_plants.any? %>
          <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 2px; margin-top: 6px;">
            <% indoor_plants.each do |plant| %>
              <a href="/plants/<%= plant.id %>" style="background: #fef2f2; border-radius: 3px; padding: 3px; text-align: center; font-size: 8px; color: var(--text-secondary); text-decoration: none;">
                <%= plant.variety_name.split.first[0..2] %>
              </a>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
  <% end %>

  <% if beds.empty? && arches.empty? && stations.empty? %>
    <div style="text-align: center; padding: 40px 20px; color: var(--text-secondary); font-size: 14px;">
      No beds set up yet.
    </div>
  <% end %>
</div>
```

**AI FAB + Drawer:**

```erb
<!-- AI FAB -->
<div @click="$refs.aiDrawer.showModal ? null : $refs.aiDrawer.showModal()" style="position: fixed; bottom: 80px; right: 16px; width: 44px; height: 44px; background: var(--green-900); border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; font-size: 18px; box-shadow: 0 2px 10px rgba(54,83,20,0.3); cursor: pointer; z-index: 40;">
  ✦
</div>

<!-- AI Drawer as dialog -->
<dialog x-ref="aiDrawer" style="position: fixed; bottom: 0; left: 0; right: 0; margin: 0; padding: 0; border: none; background: white; border-radius: 16px 16px 0 0; box-shadow: 0 -4px 20px rgba(0,0,0,0.1); max-height: 85vh; width: 100%; max-width: 100%;" x-data="aiDrawer()">
  <!-- Handle -->
  <div style="display: flex; justify-content: center; padding: 8px; cursor: pointer;" @click="$refs.aiDrawer.close()">
    <div style="width: 36px; height: 4px; background: #d1d5db; border-radius: 2px;"></div>
  </div>
  <!-- Context banner -->
  <div style="margin: 0 12px 8px; padding: 8px 12px; background: var(--green-50); border-radius: 8px; border: 1px solid #dcfce7;">
    <div style="font-size: 10px; color: var(--green-900); font-weight: 600;" x-text="'Context: ' + $data.tab + ' tab'"></div>
  </div>
  <!-- Quick actions -->
  <div style="padding: 0 12px; display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 8px;">
    <button @click="sendQuickAction('What should I do this week?')" style="font-size: 11px; padding: 6px 12px; background: var(--green-50); border: 1px solid #dcfce7; border-radius: 8px; color: var(--green-900); cursor: pointer;">What should I do this week?</button>
    <button @click="sendQuickAction('Plan next month')" style="font-size: 11px; padding: 6px 12px; background: var(--green-50); border: 1px solid #dcfce7; border-radius: 8px; color: var(--green-900); cursor: pointer;">Plan next month</button>
  </div>
  <!-- Messages -->
  <div x-ref="aiMessages" style="padding: 0 12px; max-height: 50vh; overflow-y: auto; display: flex; flex-direction: column; gap: 8px;">
    <template x-for="msg in messages" :key="msg.id">
      <div :style="msg.role === 'user' ? 'align-self: flex-end; background: var(--green-50); max-width: 80%;' : 'background: #f9fafb; max-width: 85%;'" style="border-radius: 10px; padding: 10px 12px;">
        <div x-show="msg.role === 'assistant'" style="font-size: 10px; color: var(--green-900); font-weight: 600; margin-bottom: 4px;">✦ AI Planner</div>
        <div style="font-size: 12px; color: var(--text-body); line-height: 1.5;" x-html="msg.role === 'assistant' ? marked.parse(msg.content || '') : msg.content"></div>
        <!-- Draft card -->
        <template x-if="msg.draft">
          <div style="margin-top: 8px; padding: 10px; background: var(--green-50); border: 1px solid #dcfce7; border-radius: 8px;">
            <div style="font-size: 11px; color: var(--green-900); font-weight: 600; margin-bottom: 6px;">Plan Draft</div>
            <div style="font-size: 11px; color: var(--text-secondary); margin-bottom: 8px;" x-text="(msg.draft.assignments?.length || 0) + ' plants, ' + (msg.draft.tasks?.length || 0) + ' tasks, ' + (msg.draft.successions?.length || 0) + ' successions'"></div>
            <button @click="fetch('/succession/planner/commit', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(msg.draft)}).then(() => location.reload())" style="padding: 6px 16px; background: var(--green-900); color: white; border: none; border-radius: 8px; font-size: 12px; cursor: pointer;">Create this plan</button>
          </div>
        </template>
      </div>
    </template>
  </div>
  <!-- Input -->
  <div style="padding: 12px; margin-top: 8px; border-top: 1px solid #e5e7eb;">
    <form @submit.prevent="sendMessage()" style="display: flex; gap: 8px; align-items: center;">
      <input x-model="input" type="text" placeholder="Ask about your plan..." style="flex: 1; background: #f3f4f6; border-radius: 10px; padding: 10px 14px; font-size: 12px; border: none; outline: none;">
      <button type="submit" style="width: 36px; height: 36px; background: var(--green-900); border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; font-size: 14px; border: none; cursor: pointer;">↑</button>
    </form>
  </div>
</dialog>
```

**Alpine.js aiDrawer() component:**

```javascript
function aiDrawer() {
  return {
    messages: JSON.parse(document.getElementById('planner-data')?.textContent || '[]'),
    input: '',
    sending: false,

    async sendMessage() {
      if (!this.input.trim() || this.sending) return;
      const text = this.input.trim();
      this.input = '';
      this.messages.push({ role: 'user', content: text, id: Date.now() });
      this.sending = true;

      try {
        const context = this.$root.__x.$data?.getAIContext?.() || { view: 'tasks' };
        const res = await fetch('/succession/planner/ask', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: text, context })
        });
        const { request_id } = await res.json();
        await this.pollForResponse(request_id);
      } catch(e) {
        this.messages.push({ role: 'assistant', content: 'Sorry, something went wrong.', id: Date.now() });
      }
      this.sending = false;
    },

    async pollForResponse(requestId) {
      for (let i = 0; i < 60; i++) {
        await new Promise(r => setTimeout(r, 2000));
        const res = await fetch(`/succession/planner/result/${requestId}`);
        const data = await res.json();
        if (data.status === 'done') {
          this.messages.push({ role: 'assistant', content: data.content, id: Date.now(), draft: data.draft });
          return;
        }
        if (data.status === 'error') {
          this.messages.push({ role: 'assistant', content: data.error || 'Planning failed.', id: Date.now() });
          return;
        }
      }
    },

    sendQuickAction(text) {
      this.input = text;
      this.sendMessage();
    }
  }
}
```

- [ ] **Step 2: Verify the page loads**

Run the app locally and navigate to `/succession`. Check:
- Summary strip renders with counts
- Three tabs are clickable and switch content
- Tasks tab shows tasks grouped by urgency
- Timeline tab shows bed occupancy heat-map (or empty state)
- Beds tab shows bed cards with slot grids
- AI FAB is visible and opens the drawer

- [ ] **Step 3: Run all tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb`
Expected: Some existing tests may need adjustment (see Task 5).

- [ ] **Step 4: Commit**

```bash
git add views/succession.erb
git commit -m "feat: rewrite Plan tab — tabbed layout with summary strip, timeline, beds, AI drawer"
```

---

### Task 5: Update Existing Tests for New Template

**Files:**
- Modify: `test/routes/test_succession.rb`

The existing tests check for `x-data="gantt()"` which no longer exists. Update them.

- [ ] **Step 1: Update test assertions**

Replace the existing `test_succession_page_includes_alpine_component` test:

```ruby
def test_succession_page_includes_alpine_component
  SuccessionPlan.create(
    crop: "Lettuce",
    varieties: '["Tre Colori"]',
    interval_days: 14,
    total_planned_sowings: 5,
    garden_id: @garden.id
  )

  get "/succession"
  assert_equal 200, last_response.status
  assert_includes last_response.body, 'x-data="planTab()"'
  assert_includes last_response.body, "Season Plan"
  assert_includes last_response.body, "Tasks"
  assert_includes last_response.body, "Timeline"
  assert_includes last_response.body, "Beds"
end
```

Also update `test_succession_index_has_summary_strip` (from Task 1) now that the template exists.

- [ ] **Step 2: Run all succession tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb`
Expected: All tests pass

- [ ] **Step 3: Run full test suite**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All 32+ tests pass

- [ ] **Step 4: Commit**

```bash
git add test/routes/test_succession.rb
git commit -m "test: update succession tests for new tabbed Plan tab"
```

---

## Summary

| Task | What changes | Files |
|------|-------------|-------|
| 1 | Summary counts in route | routes/succession.rb, test |
| 2 | Bed timeline API endpoint | routes/succession.rb, test |
| 3 | Context support for AI planner | routes/succession.rb |
| 4 | Full template rewrite — all 5 components | views/succession.erb |
| 5 | Update tests for new template structure | test/routes/test_succession.rb |

Total: **5 tasks**, 2 chunks. Chunk 1 = backend (Tasks 1-3), Chunk 2 = frontend (Tasks 4-5). All existing tests must pass after each task.
