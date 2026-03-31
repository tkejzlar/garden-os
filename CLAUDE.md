# GardenOS

A garden planning and management app for productive vegetable gardens. Single-user, self-hosted. Sinatra backend + React SPA frontend.

## Tech Stack

- **Backend:** Ruby/Sinatra 4, Sequel ORM, SQLite3, Puma
- **Frontend:** React 19, TypeScript, Vite, Tailwind CSS 4, Zustand
- **AI Planner:** RubyLLM with 34 registered tools, SSE streaming
- **Infra:** Single SQLite DB, file-based feature request logging in docs/gaps/

## Project Structure

```
app.rb                  # Sinatra app entry point, SPA catch-all
config/                 # database.rb, ruby_llm.rb, puma.rb
models/                 # Sequel models: bed.rb, plant.rb, garden.rb, etc.
routes/                 # Sinatra route files: beds, plants, succession, seeds, photos, dashboard, tasks
services/               # Business logic
  planner_service.rb    # AI chat orchestration, SSE streaming, tool registration
  planner_tools/        # 34 RubyLLM tool classes (the AI's capabilities)
  plan_committer.rb     # Applies draft plans to DB
  garden_logger.rb      # File-based gap/error logging
  task_generator.rb     # Creates sow tasks from succession plans
src/                    # React SPA
  pages/                # Route-level components (Dashboard, GardenDesigner, PlanHub, etc.)
  components/           # UI components (AIDrawer, BedCanvas, PlantRect, etc.)
  lib/                  # api.ts, crops.ts, markdown.ts, toast.ts
db/migrations/          # 20 Sequel migrations
test/                   # Minitest tests
dist/                   # Built SPA (deploy.sh runs vite build)
docs/gaps/              # AI-logged feature requests (YAML files)
docs/superpowers/       # Design specs and implementation plans
```

## Key Patterns

### AI Planner Architecture
- Tools are RubyLLM::Tool subclasses in `services/planner_tools/`
- Each tool has a `description`, `param` declarations, and an `execute` method
- Tools are registered in `PlannerService#chat` with `.with_tool(ToolClass)`
- System prompt is in `PlannerService#system_prompt`
- Thread-local state: `Thread.current[:planner_draft]`, `[:planner_needs_refresh]`, etc.
- SSE streaming via `send_message_streaming` yielding `{ type: "chunk" | "draft" | "refresh" | ... }`
- Frontend handles events in `AIDrawer.tsx`

### Adding a new planner tool
1. Create `services/planner_tools/my_tool.rb` (extend `RubyLLM::Tool`)
2. Add `require_relative` and `.with_tool(MyTool)` in `planner_service.rb`
3. Document it in the system prompt section of `planner_service.rb`
4. Set `Thread.current[:planner_needs_refresh] = true` if it mutates data

### Grid System
- 5cm per grid cell
- Beds have `grid_cols` and `grid_rows` derived from dimensions
- Plants occupy `grid_x, grid_y, grid_w, grid_h` rectangles
- Polygon beds use `canvas_points` (JSON array of [x,y] pairs)
- `Bed#point_in_polygon?(grid_x, grid_y)` for polygon-aware placement
- `Bed#resolve_row("front"/"back"/"middle")` for semantic positioning

### Plan Commit Flow
- AI calls `draft_plan` tool -> stored in thread-local -> sent as SSE event
- Frontend shows draft card with "Apply" button
- POST `/api/planner/commit` -> `PlanCommitter.commit!`
- Supports `"mode": "replace"` to clear target beds before applying

### Feature Request Self-Reporting
- AI logs gaps via `RequestFeatureTool` -> YAML files in `docs/gaps/`
- Dedup: fuzzy word-overlap matching prevents duplicate logging
- AI can check existing requests with `CheckFeatureRequestsTool`
- AI can resolve requests with `ResolveFeatureRequestTool`
- API: `GET /api/feature-requests`, `DELETE /api/feature-requests/duplicates`

## Development

```bash
# Install dependencies
bundle install && npm install

# Dev server (Vite proxy to Sinatra)
npm run dev     # Vite on :5173
bundle exec puma -C config/puma.rb config.ru  # Sinatra on :9292

# Run tests
ruby -Itest -e "Dir['test/**/*test*.rb'].each { |f| require_relative f }"

# Build + deploy
./deploy.sh
```

## Database
- SQLite at `db/garden_os.db` (prod) / `db/garden_os_test.db` (test)
- Migrations: `db/migrations/001_create_beds.rb` through `020_add_bed_zones_and_metadata.rb`
- Run migrations: `ruby -e "require_relative 'config/database'; Sequel::Migrator.run(DB, 'db/migrations')"`

## Testing
- Framework: Minitest + Rack::Test
- Test helper: `test/test_helper.rb` — clears all tables between tests, creates test garden
- Planner tool tests: `test/services/test_planner_*.rb` (65+ tests)
- Run specific: `ruby -Itest test/services/test_planner_crud_tools.rb`

## Notes
- The garden is in Prague, Czech Republic (zone 6b/7a, last frost ~May 13)
- Cookie-based garden switching (multi-garden support)
- Old ERB/Alpine tests exist and fail (pre-React rewrite) — ignore those
- Production serves built SPA from `dist/`, assets with immutable caching
