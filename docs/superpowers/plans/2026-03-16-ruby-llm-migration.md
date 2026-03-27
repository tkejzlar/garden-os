# Migrate AI Advisory to ruby_llm Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `anthropic` gem with `ruby_llm` so the AI advisory feature can use any LLM provider (Anthropic, OpenAI, Gemini, etc.) via a single configurable model setting.

**Architecture:** Swap the direct Anthropic API call in `AIAdvisoryService#run_daily!` with `ruby_llm`'s provider-agnostic chat interface. Add a `GARDEN_AI_MODEL` env var to select the model at runtime. Use `RubyLLM::Schema` for structured JSON responses instead of asking the LLM to output raw JSON.

**Tech Stack:** ruby_llm gem (replaces anthropic gem)

---

## File Structure

```
Changes:
├── Gemfile                              # Replace anthropic with ruby_llm
├── config/
│   └── ruby_llm.rb                      # NEW: RubyLLM configuration initializer
├── services/
│   └── ai_advisory_service.rb           # Rewrite run_daily! to use ruby_llm
├── test/
│   └── services/
│       └── test_ai_advisory_service.rb  # Update tests for new interface
└── .env.example                         # Update env var names
```

---

### Task 1: Swap gem + configure ruby_llm

**Files:**
- Modify: `Gemfile`
- Create: `config/ruby_llm.rb`
- Modify: `.env.example`

- [ ] **Step 1: Update Gemfile — replace anthropic with ruby_llm**

In `Gemfile`, replace:
```ruby
gem "anthropic", "~> 0.3"
```
with:
```ruby
gem "ruby_llm"
```

- [ ] **Step 2: Run bundle install**

Run: `bundle install`
Expected: ruby_llm installed, anthropic removed from Gemfile.lock.

- [ ] **Step 3: Create config/ruby_llm.rb**

```ruby
# config/ruby_llm.rb
require "ruby_llm"

RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"] if ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"] if ENV["ANTHROPIC_API_KEY"]
  config.gemini_api_key = ENV["GEMINI_API_KEY"] if ENV["GEMINI_API_KEY"]
end
```

- [ ] **Step 4: Update .env.example**

Replace the single `ANTHROPIC_API_KEY` line with:
```bash
# AI provider keys (set at least one)
ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
# GEMINI_API_KEY=...

# Which model to use for daily advisory (default: claude-sonnet-4-6)
GARDEN_AI_MODEL=claude-sonnet-4-6
```

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock config/ruby_llm.rb .env.example
git commit -m "feat: replace anthropic gem with ruby_llm for multi-provider AI support"
```

---

### Task 2: Rewrite AIAdvisoryService to use ruby_llm

**Files:**
- Modify: `services/ai_advisory_service.rb`
- Modify: `test/services/test_ai_advisory_service.rb`

- [ ] **Step 1: Write failing test for model configurability**

Add to `test/services/test_ai_advisory_service.rb`:

```ruby
def test_default_model
  assert_equal "claude-sonnet-4-6", AIAdvisoryService.model_id
end

def test_model_from_env
  ENV["GARDEN_AI_MODEL"] = "gpt-4o"
  assert_equal "gpt-4o", AIAdvisoryService.model_id
ensure
  ENV.delete("GARDEN_AI_MODEL")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f db/garden_os_test.db && ruby test/services/test_ai_advisory_service.rb`
Expected: FAIL — `model_id` method not defined.

- [ ] **Step 3: Rewrite ai_advisory_service.rb**

Replace the entire file with:

```ruby
# services/ai_advisory_service.rb
require "json"
require_relative "../config/ruby_llm"
require_relative "../models/plant"
require_relative "../models/task"
require_relative "../models/advisory"
require_relative "../db/seeds/seed_varieties"

class AIAdvisoryService
  DEFAULT_MODEL = "claude-sonnet-4-6"

  def self.model_id
    ENV.fetch("GARDEN_AI_MODEL", DEFAULT_MODEL)
  end

  def self.system_prompt
    <<~PROMPT
      You are a garden advisor for a productive vegetable garden in Prague, Czech Republic (zone 6b/7a).
      Climate: last frost ~May 13, first frost ~Oct 15. Continental climate with hot summers.

      You receive the current state of all plants, upcoming tasks, and weather forecast.
      Provide actionable, specific advisories. Focus on:
      - Germination progress (is it on track for the crop type?)
      - Weather-based timing recommendations
      - Succession sowing reminders
      - Potential issues (overdue germination, frost risk for tender plants)

      Respond with JSON only:
      {
        "advisories": [
          {"type": "general|plant_specific|weather", "plant": "name or null", "summary": "one sentence", "detail": "explanation"}
        ]
      }
    PROMPT
  end

  def self.build_context
    plants = Plant.exclude(lifecycle_stage: "done").all.map do |p|
      {
        variety_name: p.variety_name,
        crop_type: p.crop_type,
        stage: p.lifecycle_stage,
        days_in_stage: p.days_in_stage,
        sow_date: p.sow_date&.to_s
      }
    end

    tasks = Task.where(due_date: Date.today..(Date.today + 7))
                .exclude(status: "done").all.map do |t|
      { title: t.title, type: t.task_type, due: t.due_date.to_s }
    end

    weather = WeatherService.fetch_current rescue nil

    {
      date: Date.today.to_s,
      plants: plants,
      upcoming_tasks: tasks,
      weather: weather,
      variety_data: Varieties.all
    }
  end

  def self.parse_response(data)
    (data["advisories"] || []).map do |adv|
      {
        type: adv["type"],
        plant: adv["plant"],
        summary: adv["summary"],
        detail: adv["detail"]
      }
    end
  end

  def self.run_daily!
    context = build_context

    chat = RubyLLM.chat(model: model_id)
      .with_instructions(system_prompt)
      .with_temperature(0.3)

    response = chat.ask(JSON.pretty_generate(context))
    text = response.content

    parsed = JSON.parse(text)
    advisories = parse_response(parsed)

    advisories.each do |adv|
      plant_id = nil
      if adv[:plant]
        plant = Plant.where(variety_name: adv[:plant]).first
        plant_id = plant&.id
      end

      Advisory.create(
        date: Date.today,
        advisory_type: adv[:type],
        content: JSON.generate(adv),
        plant_id: plant_id
      )
    end

    advisories
  rescue => e
    warn "AI Advisory error: #{e.message}"
    []
  end
end
```

**Key changes from original:**
- `require "anthropic"` → `require_relative "../config/ruby_llm"`
- No more `ENV["ANTHROPIC_API_KEY"]` guard — ruby_llm handles missing keys gracefully
- `Anthropic::Client.new` + `client.messages.create(...)` → `RubyLLM.chat(model:).with_instructions().ask()`
- `response.content.first.text` → `response.content`
- Model is configurable via `GARDEN_AI_MODEL` env var

- [ ] **Step 4: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/services/test_ai_advisory_service.rb`
Expected: 5 tests, 0 failures.

- [ ] **Step 5: Run full test suite**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All 30 tests pass.

- [ ] **Step 6: Commit**

```bash
git add services/ai_advisory_service.rb test/services/test_ai_advisory_service.rb
git commit -m "feat: migrate AI advisory to ruby_llm — configurable model via GARDEN_AI_MODEL"
```

---

## Summary

| Task | What it does |
|------|-------------|
| 1 | Swap gems, configure ruby_llm, update env vars |
| 2 | Rewrite AIAdvisoryService to use ruby_llm chat API |

Total: **2 tasks**, minimal blast radius — only `ai_advisory_service.rb` and its test change.

**After migration, switch models by setting:**
```bash
GARDEN_AI_MODEL=gpt-4o          # OpenAI
GARDEN_AI_MODEL=claude-sonnet-4-6  # Anthropic (default)
GARDEN_AI_MODEL=gemini-2.0-flash   # Google
```
