# Sensor Integration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pull Hydrawise irrigation zone status and indoor temperature from Home Assistant, auto-skip watering tasks when rain or active irrigation is detected, and surface live sensor state in a dashboard strip.
**Architecture:** A new `SensorService` mirrors the `WeatherService` curl-based HA API pattern exactly — no new gems, no database tables, all data polled live per request. `TaskGenerator` gains a single `auto_skip_watering_tasks!` method that consults `SensorService` before generating or skipping tasks. The dashboard view receives `@sensor_data` from the route and renders the strip only when at least one sensor env var is present.
**Tech Stack:** Ruby (curl via backticks, same pattern as `WeatherService`), ERB, Minitest, existing HA REST API (`/api/states/:entity_id`)
**Spec:** `docs/superpowers/specs/2026-03-16-v2-features.md` — Section 3

---

## Step 1 — Create `services/sensor_service.rb`

- [ ] Create `services/sensor_service.rb` with the following complete implementation:

```ruby
require "json"

class SensorService
  def self.ha_url    = ENV.fetch("HA_URL", "http://homeassistant.local:8123")
  def self.ha_token  = ENV.fetch("HA_TOKEN", "")

  # Returns array of zone hashes: [{name:, entity_id:, state:, next_run:}]
  # state is one of: "idle", "running", "offline"
  # next_run is the HA attribute "next_cycle" (string) or nil
  def self.fetch_zones
    zone_ids = ENV.fetch("HA_HYDRAWISE_ZONES", "").split(",").map(&:strip).reject(&:empty?)
    return [] if zone_ids.empty? || ha_token.empty?

    zone_ids.map do |entity_id|
      data = ha_get("/api/states/#{entity_id}")
      next nil unless data

      attrs = data["attributes"] || {}
      raw_state = data["state"].to_s.downcase

      state = case raw_state
              when "on"  then "running"
              when "off" then "idle"
              else            "offline"
              end

      {
        name:      attrs["friendly_name"] || entity_id,
        entity_id: entity_id,
        state:     state,
        next_run:  attrs["next_cycle"]
      }
    end.compact
  rescue => e
    warn "SensorService#fetch_zones error: #{e.message}"
    []
  end

  # Returns {temp:, entity_id:, warning:} or nil if not configured / unreachable
  # warning is true when temp is outside the 25–32°C heat mat sweet spot
  def self.fetch_indoor_temp
    entity_id = ENV.fetch("HA_INDOOR_TEMP_ENTITY", "")
    return nil if entity_id.empty? || ha_token.empty?

    data = ha_get("/api/states/#{entity_id}")
    return nil unless data

    temp = data["state"].to_f
    {
      temp:      temp,
      entity_id: entity_id,
      warning:   temp < 25.0 || temp > 32.0
    }
  rescue => e
    warn "SensorService#fetch_indoor_temp error: #{e.message}"
    nil
  end

  # Returns true when the HA binary rain sensor is "on", false otherwise.
  # Returns false (not nil) when the sensor is unconfigured so callers can
  # use the result directly in boolean logic without nil-guarding.
  def self.rain_detected?
    entity_id = ENV.fetch("HA_RAIN_SENSOR", "")
    return false if entity_id.empty? || ha_token.empty?

    data = ha_get("/api/states/#{entity_id}")
    return false unless data

    data["state"].to_s.downcase == "on"
  rescue => e
    warn "SensorService#rain_detected? error: #{e.message}"
    false
  end

  # Convenience: true when any Hydrawise zone is currently running
  def self.irrigation_active?
    fetch_zones.any? { |z| z[:state] == "running" }
  end

  private

  def self.ha_get(path)
    output = `curl -s --connect-timeout 5 --max-time 10 \
      -H "Authorization: Bearer #{ha_token}" \
      -H "Content-Type: application/json" \
      "#{ha_url}#{path}" 2>&1`
    return nil if output.empty? || $?.exitstatus != 0
    JSON.parse(output)
  rescue => e
    warn "SensorService HA GET error: #{e.message}"
    nil
  end
end
```

**Notes:**
- Follows the `WeatherService` pattern verbatim: `ENV.fetch` at call-time (not class load), `curl` backtick subprocess, `JSON.parse`, `rescue => e` with `warn`.
- `fetch_zones` maps each entity ID individually — HA's `/api/states` endpoint returns one entity at a time, matching how `WeatherService#ha_get` is used.
- `irrigation_active?` is a convenience wrapper used by `TaskGenerator` so the generator never calls `fetch_zones` twice.

---

## Step 2 — Create `test/services/test_sensor_service.rb`

- [ ] Create `test/services/test_sensor_service.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../services/sensor_service"

class TestSensorService < GardenTest
  # ---------------------------------------------------------------------------
  # fetch_zones
  # ---------------------------------------------------------------------------

  def test_fetch_zones_returns_empty_when_env_not_set
    ENV.delete("HA_HYDRAWISE_ZONES")
    assert_equal [], SensorService.fetch_zones
  end

  def test_fetch_zones_parses_running_zone
    ENV["HA_HYDRAWISE_ZONES"] = "switch.hydrawise_zone_1"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = {
      "state" => "on",
      "attributes" => {
        "friendly_name" => "Zone 1 — Raised Beds",
        "next_cycle" => "2026-03-17T06:00:00"
      }
    }

    SensorService.stub(:ha_get, mock_response) do
      zones = SensorService.fetch_zones
      assert_equal 1, zones.length
      assert_equal "running", zones.first[:state]
      assert_equal "Zone 1 — Raised Beds", zones.first[:name]
      assert_equal "2026-03-17T06:00:00", zones.first[:next_run]
    end
  ensure
    ENV.delete("HA_HYDRAWISE_ZONES")
    ENV.delete("HA_TOKEN")
  end

  def test_fetch_zones_parses_idle_zone
    ENV["HA_HYDRAWISE_ZONES"] = "switch.hydrawise_zone_2"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = {
      "state" => "off",
      "attributes" => { "friendly_name" => "Zone 2" }
    }

    SensorService.stub(:ha_get, mock_response) do
      zones = SensorService.fetch_zones
      assert_equal "idle", zones.first[:state]
    end
  ensure
    ENV.delete("HA_HYDRAWISE_ZONES")
    ENV.delete("HA_TOKEN")
  end

  def test_fetch_zones_returns_offline_for_unavailable_entity
    ENV["HA_HYDRAWISE_ZONES"] = "switch.hydrawise_zone_1"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = {
      "state" => "unavailable",
      "attributes" => {}
    }

    SensorService.stub(:ha_get, mock_response) do
      zones = SensorService.fetch_zones
      assert_equal "offline", zones.first[:state]
    end
  ensure
    ENV.delete("HA_HYDRAWISE_ZONES")
    ENV.delete("HA_TOKEN")
  end

  # ---------------------------------------------------------------------------
  # fetch_indoor_temp
  # ---------------------------------------------------------------------------

  def test_fetch_indoor_temp_returns_nil_when_not_configured
    ENV.delete("HA_INDOOR_TEMP_ENTITY")
    assert_nil SensorService.fetch_indoor_temp
  end

  def test_fetch_indoor_temp_no_warning_in_range
    ENV["HA_INDOOR_TEMP_ENTITY"] = "sensor.indoor_temperature"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = { "state" => "28.5", "attributes" => {} }

    SensorService.stub(:ha_get, mock_response) do
      result = SensorService.fetch_indoor_temp
      assert_equal 28.5, result[:temp]
      assert_equal false, result[:warning]
    end
  ensure
    ENV.delete("HA_INDOOR_TEMP_ENTITY")
    ENV.delete("HA_TOKEN")
  end

  def test_fetch_indoor_temp_warning_when_too_cold
    ENV["HA_INDOOR_TEMP_ENTITY"] = "sensor.indoor_temperature"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = { "state" => "22.0", "attributes" => {} }

    SensorService.stub(:ha_get, mock_response) do
      result = SensorService.fetch_indoor_temp
      assert_equal true, result[:warning]
    end
  ensure
    ENV.delete("HA_INDOOR_TEMP_ENTITY")
    ENV.delete("HA_TOKEN")
  end

  def test_fetch_indoor_temp_warning_when_too_hot
    ENV["HA_INDOOR_TEMP_ENTITY"] = "sensor.indoor_temperature"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = { "state" => "35.0", "attributes" => {} }

    SensorService.stub(:ha_get, mock_response) do
      result = SensorService.fetch_indoor_temp
      assert_equal true, result[:warning]
    end
  ensure
    ENV.delete("HA_INDOOR_TEMP_ENTITY")
    ENV.delete("HA_TOKEN")
  end

  # ---------------------------------------------------------------------------
  # rain_detected?
  # ---------------------------------------------------------------------------

  def test_rain_detected_false_when_not_configured
    ENV.delete("HA_RAIN_SENSOR")
    refute SensorService.rain_detected?
  end

  def test_rain_detected_true_when_sensor_on
    ENV["HA_RAIN_SENSOR"] = "binary_sensor.hydrawise_rain_sensor"
    ENV["HA_TOKEN"] = "fake-token"

    SensorService.stub(:ha_get, { "state" => "on", "attributes" => {} }) do
      assert SensorService.rain_detected?
    end
  ensure
    ENV.delete("HA_RAIN_SENSOR")
    ENV.delete("HA_TOKEN")
  end

  def test_rain_detected_false_when_sensor_off
    ENV["HA_RAIN_SENSOR"] = "binary_sensor.hydrawise_rain_sensor"
    ENV["HA_TOKEN"] = "fake-token"

    SensorService.stub(:ha_get, { "state" => "off", "attributes" => {} }) do
      refute SensorService.rain_detected?
    end
  ensure
    ENV.delete("HA_RAIN_SENSOR")
    ENV.delete("HA_TOKEN")
  end

  def test_rain_detected_false_when_ha_unreachable
    ENV["HA_RAIN_SENSOR"] = "binary_sensor.hydrawise_rain_sensor"
    ENV["HA_TOKEN"] = "fake-token"

    SensorService.stub(:ha_get, nil) do
      refute SensorService.rain_detected?
    end
  ensure
    ENV.delete("HA_RAIN_SENSOR")
    ENV.delete("HA_TOKEN")
  end

  # ---------------------------------------------------------------------------
  # irrigation_active?
  # ---------------------------------------------------------------------------

  def test_irrigation_active_true_when_zone_running
    SensorService.stub(:fetch_zones, [{ state: "running", name: "Zone 1", entity_id: "x", next_run: nil }]) do
      assert SensorService.irrigation_active?
    end
  end

  def test_irrigation_active_false_when_all_idle
    SensorService.stub(:fetch_zones, [{ state: "idle", name: "Zone 1", entity_id: "x", next_run: nil }]) do
      refute SensorService.irrigation_active?
    end
  end
end
```

**Run command:**
```bash
ruby test/services/test_sensor_service.rb
```

---

## Step 3 — Enhance `TaskGenerator` with `auto_skip_watering_tasks!`

- [ ] Add `require_relative "sensor_service"` at the top of `services/task_generator.rb` (after the existing requires).

- [ ] Add `auto_skip_watering_tasks!` to the `generate_all!` call and implement the method. Edit `services/task_generator.rb`:

  In `generate_all!`, append the call:
  ```ruby
  def self.generate_all!
    generate_succession_tasks!
    generate_germination_checks!
    auto_skip_watering_tasks!
  end
  ```

  Add the new method at the bottom of the class, before the final `end`:
  ```ruby
  def self.auto_skip_watering_tasks!
    return unless sensor_skip_conditions_met?

    reason = build_skip_reason
    Task.where(task_type: "water")
        .exclude(status: %w[done skipped])
        .each do |task|
          task.update(status: "skipped", notes: [task.notes, reason].compact.join(" | "))
        end
  end

  # ---- private helpers -------------------------------------------------------

  def self.sensor_skip_conditions_met?
    SensorService.rain_detected? || SensorService.irrigation_active?
  rescue => e
    warn "TaskGenerator sensor check error: #{e.message}"
    false
  end

  def self.build_skip_reason
    if SensorService.rain_detected?
      "Auto-skipped: rain detected"
    elsif SensorService.irrigation_active?
      "Auto-skipped: irrigation active"
    else
      "Auto-skipped: sensor condition"
    end
  end
  ```

**Design notes:**
- `auto_skip_watering_tasks!` only acts on tasks with `task_type: "water"` and status not already `done` or `skipped`. This targets explicit watering tasks, not sow/check tasks.
- If `SensorService` is unreachable, the `rescue` in `sensor_skip_conditions_met?` returns `false` and no tasks are skipped — fail-open, not fail-closed.
- The skip reason is appended to existing notes rather than overwriting, preserving original context.

---

## Step 4 — Add tests for `auto_skip_watering_tasks!` to `test/services/test_task_generator.rb`

- [ ] Append the following test cases to the existing `TestTaskGenerator` class in `test/services/test_task_generator.rb`:

```ruby
  # ---------------------------------------------------------------------------
  # auto_skip_watering_tasks!
  # ---------------------------------------------------------------------------

  def test_auto_skip_watering_tasks_skips_when_rain_detected
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Water tomatoes", task_type: "water",
                       due_date: Date.today, status: "upcoming", priority: "should")

    SensorService.stub(:rain_detected?, true) do
      SensorService.stub(:irrigation_active?, false) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "skipped", task.status
    assert_includes task.notes.to_s, "Auto-skipped: rain detected"
  end

  def test_auto_skip_watering_tasks_skips_when_irrigation_active
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Water herbs", task_type: "water",
                       due_date: Date.today, status: "upcoming", priority: "should")

    SensorService.stub(:rain_detected?, false) do
      SensorService.stub(:irrigation_active?, true) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "skipped", task.status
    assert_includes task.notes.to_s, "Auto-skipped: irrigation active"
  end

  def test_auto_skip_watering_tasks_does_not_skip_when_no_conditions
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Water seedlings", task_type: "water",
                       due_date: Date.today, status: "upcoming", priority: "should")

    SensorService.stub(:rain_detected?, false) do
      SensorService.stub(:irrigation_active?, false) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "upcoming", task.status
  end

  def test_auto_skip_watering_tasks_does_not_touch_done_tasks
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Water beds", task_type: "water",
                       due_date: Date.today, status: "done", priority: "should")

    SensorService.stub(:rain_detected?, true) do
      SensorService.stub(:irrigation_active?, false) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "done", task.status
  end

  def test_auto_skip_does_not_affect_non_water_tasks
    require_relative "../../services/sensor_service"
    task = Task.create(title: "Sow Lettuce #1", task_type: "sow",
                       due_date: Date.today, status: "upcoming", priority: "should")

    SensorService.stub(:rain_detected?, true) do
      SensorService.stub(:irrigation_active?, false) do
        TaskGenerator.auto_skip_watering_tasks!
      end
    end

    task.reload
    assert_equal "upcoming", task.status
  end
```

**Run command:**
```bash
ruby test/services/test_task_generator.rb
```

---

## Step 5 — Add `@sensor_data` to the dashboard route

- [ ] Locate the dashboard route in `app.rb` (or whichever Sinatra file handles `GET /`). Add `require_relative "services/sensor_service"` near the top alongside the other service requires if not already present.

- [ ] In the `GET "/"` route handler, add sensor data fetching. The block will look like:

  ```ruby
  get "/" do
    # ... existing assignments (@weather, @today_tasks, etc.) ...

    # Sensor data — only fetch if at least one entity is configured
    if sensor_vars_configured?
      @sensor_zones    = SensorService.fetch_zones
      @sensor_temp     = SensorService.fetch_indoor_temp
      @sensor_rain     = SensorService.rain_detected?
      @sensors_present = true
    else
      @sensors_present = false
    end

    erb :dashboard
  end
  ```

  Add the private helper inside the Sinatra app (or as a module-level method):
  ```ruby
  def sensor_vars_configured?
    !ENV.fetch("HA_HYDRAWISE_ZONES", "").empty? ||
      !ENV.fetch("HA_INDOOR_TEMP_ENTITY", "").empty?
  end
  ```

**Note:** Check `app.rb` for the exact location — look for `@weather = WeatherService.fetch_current` as an anchor. Place the sensor block immediately after the weather fetch.

---

## Step 6 — Add sensor strip to `views/dashboard.erb`

- [ ] In `views/dashboard.erb`, insert the sensor strip between the alert banner block and the summary strip. The alert banner ends at `<% end %>` on line 28 (the frost risk block). The summary strip `<!-- Summary Strip -->` starts on line 31. Insert between these two blocks:

```erb
<!-- Sensor Strip (only when HA sensor env vars are configured) -->
<% if @sensors_present %>
  <div class="flex gap-2 overflow-x-auto pb-1 mb-4" style="scrollbar-width: none;">

    <% if @sensor_rain %>
      <div class="flex items-center gap-1.5 flex-shrink-0 rounded-full px-3 py-1.5 text-xs font-medium"
           style="background: #dbeafe; color: #1e40af;">
        <span style="width:8px;height:8px;border-radius:50%;background:#3b82f6;display:inline-block;flex-shrink:0;"></span>
        Rain detected
      </div>
    <% end %>

    <% Array(@sensor_zones).each do |zone| %>
      <%
        dot_color = case zone[:state]
                    when "running" then "#2563eb"   # blue
                    when "idle"    then "#16a34a"   # green
                    else                "#9ca3af"   # gray / offline
                    end
        bg_color  = case zone[:state]
                    when "running" then "#dbeafe"
                    when "idle"    then "#dcfce7"
                    else                "#f3f4f6"
                    end
        text_color = case zone[:state]
                     when "running" then "#1e40af"
                     when "idle"    then "#15803d"
                     else                "#6b7280"
                     end
      %>
      <div class="flex items-center gap-1.5 flex-shrink-0 rounded-full px-3 py-1.5 text-xs font-medium"
           style="background: <%= bg_color %>; color: <%= text_color %>;">
        <span style="width:8px;height:8px;border-radius:50%;background:<%= dot_color %>;display:inline-block;flex-shrink:0;"></span>
        <%= zone[:name] %>
        <% if zone[:state] == "running" %>
          <span style="opacity:0.7;">running</span>
        <% end %>
      </div>
    <% end %>

    <% if @sensor_temp %>
      <%
        temp_bg    = @sensor_temp[:warning] ? "#fef3c7" : "#f0fdf4"
        temp_color = @sensor_temp[:warning] ? "#92400e" : "#15803d"
        temp_icon  = @sensor_temp[:warning] ? "⚠️" : "🌡️"
      %>
      <div class="flex items-center gap-1.5 flex-shrink-0 rounded-full px-3 py-1.5 text-xs font-medium"
           style="background: <%= temp_bg %>; color: <%= temp_color %>;">
        <span><%= temp_icon %></span>
        Indoor <%= @sensor_temp[:temp] %>&deg;C
        <% if @sensor_temp[:warning] %>
          <span style="opacity:0.7;">— check heat mat</span>
        <% end %>
      </div>
    <% end %>

  </div>
<% end %>
```

**Design notes:**
- The strip uses a horizontal-scroll `flex` row with `overflow-x: auto` and `scrollbar-width: none` — same pattern used elsewhere in the app for mobile-friendly pill rows.
- Rain badge only appears when `@sensor_rain` is `true` (not just truthy) — if the sensor is unconfigured, `rain_detected?` returns `false` and the badge stays hidden.
- Each zone pill follows the spec: green = idle, blue = running, gray = offline.
- Indoor temp uses the 25–32°C range from the spec. Warning renders amber with a "check heat mat" label. In-range renders green.
- No JavaScript required — purely server-rendered ERB, consistent with the existing dashboard style.

---

## Step 7 — Update `.env.example`

- [ ] Append the following lines to `.env.example` (after the existing `APP_URL` line):

```bash
# Sensor Integration (Feature 3) — leave blank to disable sensor strip
# Comma-separated HA entity IDs for Hydrawise irrigation zones
HA_HYDRAWISE_ZONES=switch.hydrawise_zone_1,switch.hydrawise_zone_2
# Indoor temperature sensor (heat mat area) — warning shown outside 25–32°C
HA_INDOOR_TEMP_ENTITY=sensor.indoor_temperature
# Binary rain sensor — auto-skips watering tasks when "on"
HA_RAIN_SENSOR=binary_sensor.hydrawise_rain_sensor
```

---

## Step 8 — Run full test suite and commit

- [ ] Run all tests to confirm nothing is broken:

```bash
ruby test/services/test_sensor_service.rb
ruby test/services/test_task_generator.rb
ruby -Itest test/routes/test_dashboard.rb
```

Or run the full suite if a rake task exists:
```bash
rake test
# or
ruby -e "Dir['test/**/*.rb'].each { |f| require_relative f }"
```

- [ ] Stage and commit:

```bash
git add services/sensor_service.rb \
        test/services/test_sensor_service.rb \
        services/task_generator.rb \
        test/services/test_task_generator.rb \
        views/dashboard.erb \
        .env.example
```

```bash
git commit -m "$(cat <<'EOF'
feat: sensor integration — SensorService, task auto-skip, dashboard strip

- Add SensorService with fetch_zones, fetch_indoor_temp, rain_detected?
  following the same curl-based HA API pattern as WeatherService
- Enhance TaskGenerator#generate_all! with auto_skip_watering_tasks!;
  skips open watering tasks when rain or active irrigation is detected
- Add sensor strip to dashboard between alert banner and summary strip;
  renders zone status (idle/running/offline), indoor temp with heat mat
  warning, and rain badge; hidden entirely when env vars are not set
- Update .env.example with HA_HYDRAWISE_ZONES, HA_INDOOR_TEMP_ENTITY,
  HA_RAIN_SENSOR

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Verification Checklist

- [ ] `SensorService.fetch_zones` returns `[]` when `HA_HYDRAWISE_ZONES` is unset — confirmed by test
- [ ] `SensorService.rain_detected?` returns `false` (not `nil`) when unconfigured — confirmed by test
- [ ] `auto_skip_watering_tasks!` skips only `task_type: "water"` tasks — confirmed by test
- [ ] Dashboard sensor strip is completely absent from HTML when `@sensors_present` is `false`
- [ ] `.env.example` documents all three new env vars with comments
- [ ] No new database migrations required — spec explicitly states "no new tables"
- [ ] All existing tests continue to pass (no regressions to WeatherService or TaskGenerator)
