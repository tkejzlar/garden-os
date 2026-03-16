# Smart Seed Auto-Fill Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When adding a seed packet, type a variety name and an AI call auto-fills crop type, growing info, and variety-specific notes.

**Architecture:** Add a `VarietyLookupService` that calls ruby_llm with the variety name, returns structured JSON (crop_type, notes, sowing info). The seed form gets an Alpine.js "Lookup" button that calls a new API endpoint, populates form fields from the response.

**Tech Stack:** ruby_llm (already configured), Alpine.js for form reactivity

**Spec:** `docs/superpowers/specs/2026-03-16-v2-features.md` — Section 4, enhanced with AI lookup

---

## File Structure

```
Modified/Created:
├── services/variety_lookup_service.rb   # NEW — AI-powered variety lookup
├── routes/seeds.rb                      # MODIFY — add GET /api/seeds/lookup?q=variety
├── views/seeds/show.erb                 # MODIFY — add lookup button + Alpine.js auto-fill
├── test/services/test_variety_lookup.rb  # NEW — test parsing
```

---

### Task 1: VarietyLookupService

**Files:**
- Create: `services/variety_lookup_service.rb`
- Create: `test/services/test_variety_lookup_service.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/services/test_variety_lookup_service.rb
require_relative "../test_helper"
require_relative "../../services/variety_lookup_service"

class TestVarietyLookupService < GardenTest
  def test_parses_valid_response
    mock_json = {
      "crop_type" => "tomato",
      "variety_notes" => "Marmande-type beefsteak from Spain, 75-80 days to maturity",
      "days_to_maturity" => "75-80",
      "frost_tender" => true,
      "sow_indoor_weeks_before_last_frost" => 8,
      "direct_sow" => false
    }
    result = VarietyLookupService.parse_response(mock_json)
    assert_equal "tomato", result[:crop_type]
    assert_includes result[:notes], "Marmande"
    assert result[:frost_tender]
  end

  def test_system_prompt_mentions_json
    prompt = VarietyLookupService.system_prompt
    assert_includes prompt, "JSON"
  end

  def test_handles_empty_response
    result = VarietyLookupService.parse_response({})
    assert_nil result[:crop_type]
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `rm -f db/garden_os_test.db && ruby test/services/test_variety_lookup_service.rb`

- [ ] **Step 3: Implement VarietyLookupService**

```ruby
# services/variety_lookup_service.rb
require "json"
require_relative "../config/ruby_llm"

class VarietyLookupService
  def self.model_id
    ENV.fetch("GARDEN_AI_MODEL", "gpt-4o")
  end

  def self.system_prompt
    <<~PROMPT
      You are a garden variety identification expert. Given a plant variety name,
      identify what it is and provide growing information.

      Respond with JSON only — no markdown, no explanation:
      {
        "crop_type": "tomato|pepper|cucumber|lettuce|radish|herb|flower|pea|bean|other",
        "variety_notes": "Brief description: origin, fruit type, flavor, disease resistance, etc.",
        "days_to_maturity": "65-75",
        "frost_tender": true,
        "sow_indoor_weeks_before_last_frost": 8,
        "direct_sow": false,
        "germination_days": "5-14",
        "germination_temp_ideal": 25,
        "spacing_cm": 45,
        "height_cm": "150-180",
        "sun": "full",
        "notes": "Any special growing tips for Prague climate (zone 6b/7a, last frost ~May 13)"
      }

      If you don't recognize the variety name, make your best guess based on the name
      and note your uncertainty in variety_notes. Set crop_type to your best guess.
    PROMPT
  end

  def self.lookup(variety_name)
    return nil if variety_name.nil? || variety_name.strip.empty?

    chat = RubyLLM.chat(model: model_id)
      .with_instructions(system_prompt)
      .with_temperature(0.2)

    response = chat.ask("Variety: #{variety_name.strip}")
    parsed = JSON.parse(response.content)
    parse_response(parsed)
  rescue => e
    warn "VarietyLookup error: #{e.message}"
    nil
  end

  def self.parse_response(data)
    return { crop_type: nil, notes: nil } if data.nil? || data.empty?

    notes_parts = [
      data["variety_notes"],
      data["days_to_maturity"] ? "#{data["days_to_maturity"]} days to maturity" : nil,
      data["height_cm"] ? "Height: #{data["height_cm"]}cm" : nil,
      data["spacing_cm"] ? "Spacing: #{data["spacing_cm"]}cm" : nil,
      data["germination_days"] ? "Germination: #{data["germination_days"]} days at #{data["germination_temp_ideal"]}°C" : nil,
      data["direct_sow"] ? "Can direct sow" : nil,
      data["frost_tender"] ? "Frost tender" : "Frost hardy",
      data["sow_indoor_weeks_before_last_frost"] ? "Start indoors #{data["sow_indoor_weeks_before_last_frost"]} weeks before last frost" : nil,
      data["notes"]
    ].compact

    {
      crop_type: data["crop_type"],
      notes: notes_parts.join(". "),
      frost_tender: data["frost_tender"],
      direct_sow: data["direct_sow"],
      days_to_maturity: data["days_to_maturity"],
      sow_indoor_weeks: data["sow_indoor_weeks_before_last_frost"],
      raw: data
    }
  end
end
```

- [ ] **Step 4: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/services/test_variety_lookup_service.rb`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add services/variety_lookup_service.rb test/services/test_variety_lookup_service.rb
git commit -m "feat: VarietyLookupService — AI-powered variety identification"
```

---

### Task 2: Lookup API Endpoint

**Files:**
- Modify: `routes/seeds.rb`
- Modify: `test/routes/test_seeds.rb`

- [ ] **Step 1: Add lookup route to routes/seeds.rb**

Add BEFORE the `get "/seeds/new"` route (Sinatra first-match):

```ruby
  # AI variety lookup
  get "/api/seeds/lookup" do
    variety = params[:q].to_s.strip
    halt 400, json(error: "q parameter required") if variety.empty?

    require_relative "../services/variety_lookup_service"
    result = VarietyLookupService.lookup(variety)

    if result
      json result
    else
      halt 503, json(error: "Lookup failed — check AI provider config")
    end
  end
```

- [ ] **Step 2: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/routes/test_seeds.rb`
Expected: Existing tests still pass.

- [ ] **Step 3: Commit**

```bash
git add routes/seeds.rb
git commit -m "feat: add GET /api/seeds/lookup AI variety endpoint"
```

---

### Task 3: Smart Seed Form with Auto-Fill

**Files:**
- Modify: `views/seeds/show.erb`

- [ ] **Step 1: Rewrite the form with Alpine.js auto-fill**

Replace the form section in `views/seeds/show.erb`. The new form adds:

1. An Alpine.js `x-data` wrapper with `lookup()` method
2. A "Look up" button next to the variety name input
3. On click: calls `GET /api/seeds/lookup?q=<variety_name>`
4. On response: auto-fills crop_type, notes fields
5. Shows a loading spinner during the AI call
6. Shows the AI-generated variety notes as a dismissible info card

The Alpine.js component:

```javascript
x-data="{
  loading: false,
  looked_up: false,
  ai_notes: '',
  async lookup() {
    const name = this.$refs.variety_name.value.trim();
    if (!name) return;
    this.loading = true;
    try {
      const resp = await fetch('/api/seeds/lookup?q=' + encodeURIComponent(name));
      if (!resp.ok) throw new Error('Lookup failed');
      const data = await resp.json();
      if (data.crop_type) this.$refs.crop_type.value = data.crop_type;
      if (data.notes) {
        this.$refs.notes.value = data.notes;
        this.ai_notes = data.notes;
      }
      this.looked_up = true;
    } catch(e) {
      console.error(e);
      this.ai_notes = 'Lookup failed — try again or fill in manually.';
    } finally {
      this.loading = false;
    }
  }
}"
```

The variety name field gets a companion button:
```html
<div class="flex gap-2">
  <input type="text" name="variety_name" x-ref="variety_name" required
         value="<%= @packet.variety_name %>" class="flex-1 rounded-lg px-3 py-2.5 text-sm border"
         style="border-color: #e5e7eb;">
  <button type="button" @click="lookup()" :disabled="loading"
          class="px-3 py-2 rounded-lg text-sm font-medium whitespace-nowrap"
          style="background: var(--green-900); color: white;">
    <span x-show="!loading">🔍 Look up</span>
    <span x-show="loading">Looking up...</span>
  </button>
</div>
```

After the notes field, show the AI info card if available:
```html
<template x-if="looked_up && ai_notes">
  <div class="rounded-lg px-3 py-2.5 text-xs" style="background: #f0fdf4; color: #365314; border: 1px solid #86efac;">
    <strong>AI says:</strong> <span x-text="ai_notes"></span>
  </div>
</template>
```

- [ ] **Step 2: Test manually**

Start puma, go to `/seeds/new`, type "Raf" in the variety name, click "Look up". Should auto-fill crop_type as "tomato" and populate notes with variety details.

- [ ] **Step 3: Run existing tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All tests pass (the AI lookup is API-only, doesn't affect form post tests).

- [ ] **Step 4: Commit**

```bash
git add views/seeds/show.erb
git commit -m "feat: smart seed form — AI auto-fills variety details on lookup"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | VarietyLookupService (AI call + parsing) | services/variety_lookup_service.rb |
| 2 | API endpoint GET /api/seeds/lookup | routes/seeds.rb |
| 3 | Smart form with lookup button + auto-fill | views/seeds/show.erb |

Total: **3 tasks**, minimal blast radius.
