# AI Garden Planner — Design Spec

> A conversational AI assistant in the Plan tab that helps design the garden season. User describes what crops they want, AI knows the bed layout and climate, produces a plan with bed assignments, succession schedules, and sowing tasks.

---

## Architecture

Three layers:

1. **Chat UI** — Alpine.js chat interface at the top of the Plan tab (`views/succession.erb`). Messages persist in a `planner_messages` table. Collapsible to show just the Gantt below.
2. **PlannerService** — Ruby service managing the conversation. Builds system prompt, registers ruby_llm tools, sends messages, parses responses.
3. **Tool functions** — Ruby methods the AI can invoke to query garden data and draft structured plans.

### Flow

```
User: "I want 20 tomatoes, succession lettuce, herbs"
  ↓
PlannerService sends to LLM with tools registered
  ↓
AI calls get_beds() → sees 6 beds with dimensions
AI calls get_seed_inventory() → sees available seed packets
  ↓
AI calls draft_plan({ assignments: [...], successions: [...], tasks: [...] })
  ↓
Draft rendered as visual preview cards in chat (not yet in DB)
  ↓
User: "Move peppers to Corner" → AI revises, calls draft_plan again
  ↓
User clicks "Create this plan" → POST /succession/planner/commit
  ↓
Server creates Plants, SuccessionPlans, Tasks, bed assignments in one transaction
  ↓
Gantt chart + Garden view + Plants list all populated
```

---

## AI Tools (Function Calling)

Registered via ruby_llm's tool system:

| Tool | Parameters | Returns |
|------|-----------|---------|
| `get_beds` | none | All beds with dimensions, rows, slots, current plants |
| `get_seed_inventory` | none | All seed packets: variety, crop_type, source, notes |
| `get_plants` | none | Active plants with stages, bed assignments |
| `get_succession_plans` | none | Existing plans with completion status |
| `get_weather_summary` | none | Current weather + 3-day forecast |
| `draft_plan` | `summary`, `assignments[]`, `successions[]`, `tasks[]` | Confirms draft stored, tells AI to present it |

### `draft_plan` payload schema

```json
{
  "summary": "Human-readable plan overview",
  "assignments": [
    {
      "bed_name": "BB1",
      "row_name": "A",
      "slot_position": 1,
      "variety_name": "Raf",
      "crop_type": "tomato",
      "source": "Reinsaat"
    }
  ],
  "successions": [
    {
      "crop": "Lettuce",
      "varieties": ["Tre Colori", "Lollo Rossa"],
      "interval_days": 18,
      "season_start": "2026-04-01",
      "season_end": "2026-09-30",
      "total_sowings": 8,
      "target_beds": ["SB1", "SB2"]
    }
  ],
  "tasks": [
    {
      "title": "Sow peppers indoors",
      "task_type": "sow",
      "due_date": "2026-03-01",
      "priority": "must",
      "notes": "All 6 pepper varieties — heat mat at 28°C",
      "related_beds": ["Corner"],
      "related_varieties": ["Habanero", "Roviga"]
    }
  ]
}
```

---

## Data Model

### New table: `planner_messages`

```
planner_messages
├── id (primary key)
├── role (string, not null) — "user", "assistant", "system"
├── content (text, not null) — message text
├── draft_payload (text, nullable) — JSON draft_plan payload (only on draft messages)
├── created_at (datetime)
```

No conversation ID needed — single user, one active conversation. "New conversation" deletes all messages.

### No changes to existing tables

Plants, Tasks, SuccessionPlans, Beds — all created through existing models when the draft is committed. No schema changes needed.

---

## Chat UI

### Layout (in Plan tab, above Gantt)

```
┌─────────────────────────────────────────┐
│ Plan                    [New chat] [▼]  │  ← header with collapse toggle
├─────────────────────────────────────────┤
│                                         │
│  🤖 Hi! I'm your garden planner.       │  ← AI messages (white cards, left)
│     What would you like to grow         │
│     this season?                        │
│                                         │
│          I want 20 tomato varieties,  📩│  ← User messages (green, right)
│          lettuce succession, herbs      │
│                                         │
│  🤖 Let me check your beds...          │
│     [calling get_beds...]               │  ← tool call indicator
│                                         │
│  🤖 Here's my proposal:                │
│  ┌─── Plan Draft ──────────────────┐   │  ← draft card (special rendering)
│  │ BB1: Raf, Marmande, Liguria...  │   │
│  │ BB2: Roma, San Marzano...       │   │
│  │ SB1: Lettuce succession (8x)    │   │
│  │ 12 tasks created                │   │
│  │                                  │   │
│  │ [Create this plan]              │   │
│  └──────────────────────────────────┘   │
│                                         │
│  ┌─────────────────────────────┐ [Send] │  ← input
│  │ Type a message...           │        │
│  └─────────────────────────────┘        │
├─────────────────────────────────────────┤
│ Active Plans (existing plan cards)      │  ← existing plan management UI
├─────────────────────────────────────────┤
│ Gantt Chart (existing)                  │  ← existing Gantt
└─────────────────────────────────────────┘
```

### Message rendering

- **User messages:** Right-aligned, green background bubble
- **AI text messages:** Left-aligned, white card
- **Tool call indicators:** Small gray text ("Looking up your beds...") — shown while AI is thinking
- **Draft cards:** Special rendering with bed assignment summary, task count, succession info. "Create this plan" button.
- **Committed card:** After plan is created, the draft card changes to "Plan created ✓" with links to the Gantt

### Chat controls

- **Send button** — POST `/succession/planner/message`
- **New chat button** — DELETE `/succession/planner/messages` + creates fresh welcome message
- **Collapse toggle** — hides chat, shows just a "Chat with planner" button to expand

---

## Routes

| Method | Path | What |
|--------|------|------|
| GET | `/succession` | Existing page + loads chat messages |
| POST | `/succession/planner/message` | Send a user message, get AI response |
| POST | `/succession/planner/commit` | Commit a draft plan to the database |
| DELETE | `/succession/planner/messages` | Clear conversation, start fresh |

### POST `/succession/planner/message`

Request: `{ message: "I want 20 tomato varieties" }`

Response (JSON — no streaming for v1, defer to follow-up):
```json
{
  "messages": [
    { "role": "assistant", "content": "Let me check your beds..." },
    { "role": "assistant", "content": "Here's my proposal:", "draft_payload": { ... } }
  ]
}
```

### POST `/succession/planner/commit`

Request: `{ draft_payload: { ...the JSON from draft_plan... } }`

Response: `{ success: true, created: { plants: 26, tasks: 12, succession_plans: 1 } }`

**Validation (before creating anything):**
1. Parse the draft payload
2. Validate ALL referenced bed names exist in the DB — reject with error listing invalid names
3. Validate row/slot references where provided — warn (don't reject) if missing, create plant without slot assignment
4. Return `{ success: false, errors: ["Bed 'XYZ' not found"] }` on validation failure

**Commit logic (in a DB transaction):**

**Assignments → Plants:**
```ruby
assignments.each do |a|
  bed = Bed.where(name: a["bed_name"]).first
  row = bed ? Row.where(bed_id: bed.id, name: a["row_name"]).first : nil
  slot = row ? Slot.where(row_id: row.id, position: a["slot_position"]).first : nil

  Plant.create(
    variety_name: a["variety_name"],
    crop_type: a["crop_type"],
    source: a["source"],
    slot_id: slot&.id,
    lifecycle_stage: "seed_packet"
  )
end
```

**Successions → SuccessionPlan + Tasks:**
```ruby
successions.each do |s|
  plan = SuccessionPlan.create(
    crop: s["crop"],
    varieties: s["varieties"].to_json,
    interval_days: s["interval_days"],
    season_start: Date.parse(s["season_start"]),
    season_end: Date.parse(s["season_end"]),
    total_planned_sowings: s["total_sowings"],
    target_beds: s["target_beds"].to_json
  )
  # Generate all tasks for this plan
  TaskGenerator.generate_for_plan!(plan)
end
```

**Tasks → Task records:**
```ruby
tasks.each do |t|
  task = Task.create(
    title: t["title"],
    task_type: t["task_type"],
    due_date: Date.parse(t["due_date"]),
    priority: t["priority"] || "should",
    status: "upcoming",
    notes: t["notes"]
  )
  # Link to beds if specified
  (t["related_beds"] || []).each do |bed_name|
    bed = Bed.where(name: bed_name).first
    DB[:tasks_beds].insert(task_id: task.id, bed_id: bed.id) if bed
  end
end
```

**Plant ↔ SuccessionPlan linkage:** Plants created from succession sowings get `succession_group_id` set to the `SuccessionPlan#id`. This uses the existing `plants.succession_group_id` column.

---

## PlannerService

```ruby
class PlannerService
  attr_reader :last_draft

  def self.model_id  = ENV.fetch("GARDEN_AI_MODEL", "gpt-4o")
  def self.provider
    m = model_id
    if m.start_with?("claude") then :anthropic
    elsif m.start_with?("gemini") then :gemini
    else :openai
    end
  end

  def initialize
    @last_draft = nil
    @chat = RubyLLM.chat(model: self.class.model_id, provider: self.class.provider, assume_model_exists: true)
      .with_instructions(system_prompt)
      .with_tool(GetBedsTool)
      .with_tool(GetSeedInventoryTool)
      .with_tool(GetPlantsTool)
      .with_tool(GetSuccessionPlansTool)
      .with_tool(GetWeatherTool)
      .with_tool(DraftPlanTool)

    # Replay conversation history so the AI has context
    PlannerMessage.order(:created_at).all.each do |msg|
      @chat.messages << { role: msg.role, content: msg.content }
    end
  end

  def send_message(user_text)
    # Save user message
    PlannerMessage.create(role: "user", content: user_text)

    # DraftPlanTool stores payload via thread-local so we can retrieve it
    Thread.current[:planner_draft] = nil

    # Send to LLM (handles tool calls automatically via ruby_llm)
    response = @chat.ask(user_text)

    # Check if AI called draft_plan
    @last_draft = Thread.current[:planner_draft]

    # Save assistant response
    PlannerMessage.create(
      role: "assistant",
      content: response.content,
      draft_payload: @last_draft&.to_json
    )

    response
  end
end
```

**Conversation history replay:** On each request, `PlannerService.new` creates a fresh `@chat` and replays all stored messages into it. This means the AI always has the full conversation context, even after server restarts. Since this is a single-user app with short conversations (10-20 messages), the token cost is trivial.

**DraftPlanTool side-effect:** The tool stores its payload via `Thread.current[:planner_draft]`. After `.ask()` returns, the service reads it. This avoids class variables (not thread-safe) and instance variable sharing (tool classes don't have access to the service instance).

```ruby
class DraftPlanTool < RubyLLM::Tool
  description "Create a draft garden plan with bed assignments, succession schedules, and tasks"
  param :payload, type: :string, desc: "JSON string with summary, assignments, successions, tasks"

  def execute(payload:)
    parsed = JSON.parse(payload)
    Thread.current[:planner_draft] = parsed
    "Draft plan stored. Present the summary to the user and tell them they can click 'Create this plan' to commit it."
  end
end
```

### Tool classes (ruby_llm pattern)

```ruby
class GetBedsTool < RubyLLM::Tool
  description "Get all garden beds with dimensions, rows, slots, and current plant assignments"

  def execute
    beds = Bed.all.map { |b| { name: b.name, type: b.bed_type, ... } }
    beds.to_json
  end
end
```

---

## Seeds → Plants Bridge

Plants are created from the planner's commit endpoint (see "Commit logic" above). The planner is the primary way plants enter the system — from plan draft to committed records.

A future enhancement (not in this spec) could add a "Sow" button on the Seeds tab for creating individual plants outside the planner.

---

## System Prompt

```
You are a garden planning consultant for a productive vegetable garden in Prague,
Czech Republic (zone 6b/7a, last frost ~May 13, first frost ~Oct 15, continental climate).

ALWAYS use the available tools to look up the garden's actual data before making
recommendations. Don't assume — check the beds, seeds, and existing plants.

CRITICAL: When referencing beds, rows, or slots in your draft_plan, use ONLY the
exact names and positions returned by get_beds. Never invent bed or row names.

When the user describes what they want to grow, help them create a complete plan:
1. First, check what beds are available and their dimensions
2. Check what seeds they already have
3. Propose bed assignments considering: sun exposure, spacing, companion planting,
   crop rotation, and the user's preferences
4. Set up succession schedules for crops that benefit from them
5. Create a task timeline with sowing dates (indoor + outdoor), transplant dates,
   and other key milestones

When you have a complete plan, call the draft_plan tool with ALL the structured data.
The user will see a visual preview and can request changes before committing.

Be conversational, practical, and opinionated. If the user asks for something that
doesn't make horticultural sense, say so and suggest alternatives.

Prague climate notes:
- Indoor sowing: Feb-April (peppers early Feb, tomatoes early March)
- Last frost: ~May 13 (Ice Saints)
- Transplant tender crops: after May 15
- Growing season: May-October
- First frost: ~Oct 15
```

---

## What's NOT changing

- Gantt chart — stays as-is below the chat
- Plan management cards — stay between chat and Gantt
- Existing routes — all preserved
- Garden/Beds/Seeds/Dashboard — no changes
- Task generation logic — planner creates tasks directly, doesn't use TaskGenerator
