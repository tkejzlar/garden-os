# Seed Inventory Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Seed Inventory page where users can track seed packets — variety, quantity, sow-by date — grouped by crop type with expiry warnings.
**Architecture:** New `seed_packets` table (no FKs) with a standalone Sequel model; CRUD routes in `routes/seeds.rb` follow the existing Sinatra class-reopen pattern; two ERB views under `views/seeds/`; a 5th "Seeds" tab added to the bottom nav in `views/layout.erb`.
**Tech Stack:** Sequel migration (SQLite), Sinatra routes, ERB views, Minitest + Rack::Test
**Spec:** `docs/superpowers/specs/2026-03-16-v2-features.md` — Section 4

---

## Task 1 — Migration + Model

### 1.1 Create migration

- [ ] Create `db/migrations/008_create_seed_packets.rb`:

```ruby
Sequel.migration do
  change do
    create_table(:seed_packets) do
      primary_key :id
      String :variety_name, null: false
      String :crop_type, null: false
      String :source
      Integer :quantity_remaining
      Date :sow_by_date
      Date :purchase_date
      String :url
      String :notes, text: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      index :crop_type
    end
  end
end
```

> Note: No foreign keys — seed packets are standalone records.

### 1.2 Create model

- [ ] Create `models/seed_packet.rb`:

```ruby
require_relative "../config/database"

class SeedPacket < Sequel::Model
  def expired?
    sow_by_date && sow_by_date < Date.today
  end

  def expiring_soon?
    sow_by_date && !expired? && sow_by_date <= Date.today + 180
  end

  def out_of_stock?
    !quantity_remaining.nil? && quantity_remaining <= 0
  end
end
```

### 1.3 Run and verify

- [ ] Run migration:
  ```
  bundle exec rake db:migrate
  ```
- [ ] Confirm table exists in SQLite:
  ```
  sqlite3 db/garden_os.db ".schema seed_packets"
  ```

### 1.4 Commit

```bash
git add db/migrations/008_create_seed_packets.rb models/seed_packet.rb
git commit -m "feat: add seed_packets migration and SeedPacket model"
```

---

## Task 2 — Routes + Tests

### 2.1 Create routes file

- [ ] Create `routes/seeds.rb`:

```ruby
require_relative "../models/seed_packet"

class GardenApp
  get "/seeds" do
    @packets = SeedPacket.order(:crop_type, :variety_name).all
    erb :"seeds/index"
  end

  get "/seeds/new" do
    @packet = SeedPacket.new
    erb :"seeds/show"
  end

  get "/seeds/:id" do
    @packet = SeedPacket[params[:id].to_i]
    halt 404, "Seed packet not found" unless @packet
    erb :"seeds/show"
  end

  post "/seeds" do
    SeedPacket.create(
      variety_name:       params[:variety_name].to_s.strip,
      crop_type:          params[:crop_type].to_s.strip,
      source:             params[:source].to_s.strip.then { |v| v.empty? ? nil : v },
      quantity_remaining: params[:quantity_remaining].to_s.strip.then { |v| v.empty? ? nil : v.to_i },
      sow_by_date:        params[:sow_by_date].to_s.strip.then { |v| v.empty? ? nil : Date.parse(v) },
      purchase_date:      params[:purchase_date].to_s.strip.then { |v| v.empty? ? nil : Date.parse(v) },
      url:                params[:url].to_s.strip.then { |v| v.empty? ? nil : v },
      notes:              params[:notes].to_s.strip.then { |v| v.empty? ? nil : v },
      created_at:         Time.now,
      updated_at:         Time.now
    )
    redirect "/seeds"
  end

  patch "/seeds/:id" do
    packet = SeedPacket[params[:id].to_i]
    halt 404 unless packet
    packet.update(
      variety_name:       params[:variety_name].to_s.strip,
      crop_type:          params[:crop_type].to_s.strip,
      source:             params[:source].to_s.strip.then { |v| v.empty? ? nil : v },
      quantity_remaining: params[:quantity_remaining].to_s.strip.then { |v| v.empty? ? nil : v.to_i },
      sow_by_date:        params[:sow_by_date].to_s.strip.then { |v| v.empty? ? nil : Date.parse(v) },
      purchase_date:      params[:purchase_date].to_s.strip.then { |v| v.empty? ? nil : Date.parse(v) },
      url:                params[:url].to_s.strip.then { |v| v.empty? ? nil : v },
      notes:              params[:notes].to_s.strip.then { |v| v.empty? ? nil : v },
      updated_at:         Time.now
    )
    redirect "/seeds/#{packet.id}"
  end

  delete "/seeds/:id" do
    packet = SeedPacket[params[:id].to_i]
    halt 404 unless packet
    packet.destroy
    redirect "/seeds"
  end

  get "/api/seeds" do
    json SeedPacket.order(:crop_type, :variety_name).all.map(&:values)
  end
end
```

> Note: Sinatra does not natively support `PATCH` from HTML forms. The show view (Task 3) uses a `POST` with a hidden `_method=PATCH` field and the `rack-methodoverride` middleware (already present in Sinatra::Base by default when `method_override` is enabled). Confirm `set :method_override, true` is present in `app.rb` `configure` block, or add it.

### 2.2 Create test file

- [ ] Create `test/routes/test_seeds.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../app"

class TestSeeds < GardenTest
  def test_seeds_index_empty
    get "/seeds"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "No seed packets tracked yet"
  end

  def test_seeds_index_lists_packets
    SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                      created_at: Time.now, updated_at: Time.now)
    get "/seeds"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sungold"
  end

  def test_seeds_show
    packet = SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                               created_at: Time.now, updated_at: Time.now)
    get "/seeds/#{packet.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sungold"
  end

  def test_seeds_show_404
    get "/seeds/999999"
    assert_equal 404, last_response.status
  end

  def test_create_seed_packet
    post "/seeds", variety_name: "Sungold", crop_type: "tomato",
                   source: "Loukykvět", quantity_remaining: "10"
    assert_equal 302, last_response.status
    assert_equal 1, SeedPacket.count
    packet = SeedPacket.first
    assert_equal "Sungold", packet.variety_name
    assert_equal "tomato",  packet.crop_type
    assert_equal 10,        packet.quantity_remaining
  end

  def test_create_seed_packet_with_sow_by_date
    post "/seeds", variety_name: "Basil", crop_type: "herb",
                   sow_by_date: "2027-01-01"
    assert_equal 302, last_response.status
    assert_equal Date.new(2027, 1, 1), SeedPacket.first.sow_by_date
  end

  def test_update_seed_packet
    packet = SeedPacket.create(variety_name: "Old Name", crop_type: "tomato",
                               created_at: Time.now, updated_at: Time.now)
    patch "/seeds/#{packet.id}", variety_name: "New Name", crop_type: "tomato"
    assert_equal 302, last_response.status
    assert_equal "New Name", packet.reload.variety_name
  end

  def test_delete_seed_packet
    packet = SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                               created_at: Time.now, updated_at: Time.now)
    delete "/seeds/#{packet.id}"
    assert_equal 302, last_response.status
    assert_equal 0, SeedPacket.count
  end

  def test_api_seeds
    SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                      created_at: Time.now, updated_at: Time.now)
    get "/api/seeds"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 1, data.length
    assert_equal "Sungold", data.first["variety_name"]
  end

  def test_seeds_grouped_by_crop_type
    SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                      created_at: Time.now, updated_at: Time.now)
    SeedPacket.create(variety_name: "Genovese", crop_type: "herb",
                      created_at: Time.now, updated_at: Time.now)
    get "/seeds"
    body = last_response.body
    assert_includes body, "tomato"
    assert_includes body, "herb"
    tomato_pos = body.index("tomato")
    herb_pos   = body.index("herb")
    assert herb_pos > tomato_pos, "herb section should appear after tomato (alphabetical)"
  end

  def test_expired_model_helper
    packet = SeedPacket.new(sow_by_date: Date.today - 1)
    assert packet.expired?
    refute packet.expiring_soon?
  end

  def test_expiring_soon_model_helper
    packet = SeedPacket.new(sow_by_date: Date.today + 90)
    refute packet.expired?
    assert packet.expiring_soon?
  end

  def test_out_of_stock_model_helper
    assert SeedPacket.new(quantity_remaining: 0).out_of_stock?
    assert SeedPacket.new(quantity_remaining: -1).out_of_stock?
    refute SeedPacket.new(quantity_remaining: 1).out_of_stock?
    refute SeedPacket.new(quantity_remaining: nil).out_of_stock?
  end
end
```

### 2.3 Run tests

- [ ] Run tests:
  ```
  bundle exec ruby -Itest test/routes/test_seeds.rb
  ```
  All tests should pass (green).

### 2.4 Commit

```bash
git add routes/seeds.rb test/routes/test_seeds.rb
git commit -m "feat: add seed inventory routes and tests"
```

---

## Task 3 — Views

### 3.1 Create views directory

- [ ] Create `views/seeds/` directory:
  ```
  mkdir -p views/seeds
  ```

### 3.2 Create index view

- [ ] Create `views/seeds/index.erb`:

```erb
<!-- Page Header -->
<div class="flex items-center justify-between mb-6">
  <h1 class="text-2xl font-bold" style="color: var(--text-primary)">Seeds</h1>
  <a href="/seeds/new"
     class="text-sm px-3 py-1.5 rounded-lg font-medium"
     style="background: var(--green-900); color: white;">
    + Add
  </a>
</div>

<% if @packets.empty? %>
  <div class="text-center py-12" style="color: var(--text-secondary)">
    <p class="text-base">No seed packets tracked yet. Add your first packet.</p>
  </div>
<% else %>
  <% @packets.group_by(&:crop_type).sort.each do |crop, packets| %>
    <p class="mb-2 mt-5 first:mt-0"
       style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; font-weight: 600; color: var(--gray-500);">
      <%= crop.capitalize %>
    </p>

    <div class="space-y-2 mb-2">
      <% packets.each do |packet| %>
        <a href="/seeds/<%= packet.id %>"
           class="flex items-center justify-between gap-3 px-4 py-3 block"
           style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow); text-decoration: none;">

          <div class="flex-1 min-w-0">
            <p class="font-semibold truncate" style="color: var(--text-primary);">
              <%= packet.variety_name %>
            </p>
            <p class="text-sm mt-0.5" style="color: var(--text-secondary);">
              <% if packet.source %>
                <%= packet.source %>
                <% if !packet.quantity_remaining.nil? %>&nbsp;&middot;<% end %>
              <% end %>
              <% unless packet.quantity_remaining.nil? %>
                <%= packet.quantity_remaining %> remaining
              <% end %>
            </p>
          </div>

          <!-- Status Pills -->
          <div class="flex gap-2 flex-shrink-0">
            <% if packet.out_of_stock? %>
              <span class="text-xs px-2 py-0.5 rounded-full font-medium"
                    style="background: #f3f4f6; color: var(--gray-500);">
                Out of stock
              </span>
            <% end %>
            <% if packet.expired? %>
              <span class="text-xs px-2 py-0.5 rounded-full font-medium"
                    style="background: #fef2f2; color: #991b1b;">
                Expired
              </span>
            <% elsif packet.expiring_soon? %>
              <span class="text-xs px-2 py-0.5 rounded-full font-medium"
                    style="background: var(--alert-amber-bg); color: #92400e;">
                Sow by <%= packet.sow_by_date.strftime("%b %Y") %>
              </span>
            <% end %>
          </div>

        </a>
      <% end %>
    </div>
  <% end %>
<% end %>
```

### 3.3 Create show/edit view

- [ ] Create `views/seeds/show.erb`:

```erb
<% new_record = @packet.new? %>

<!-- Back Link -->
<a href="/seeds" class="text-sm hover:underline mb-5 inline-block" style="color: var(--green-900);">
  &larr; All seeds
</a>

<!-- Page Header -->
<% unless new_record %>
  <div class="mb-5">
    <h1 class="text-2xl font-bold" style="color: var(--text-primary); letter-spacing: -0.5px;">
      <%= @packet.variety_name %>
    </h1>
    <p class="text-sm capitalize mt-1" style="color: var(--text-secondary);">
      <%= @packet.crop_type %>
      <% if @packet.source %>&mdash; <%= @packet.source %><% end %>
    </p>
  </div>

  <!-- Status badges -->
  <div class="flex gap-2 mb-5">
    <% if @packet.out_of_stock? %>
      <span class="text-sm px-3 py-1 rounded-full font-medium"
            style="background: #f3f4f6; color: var(--gray-500);">
        Out of stock
      </span>
    <% end %>
    <% if @packet.expired? %>
      <span class="text-sm px-3 py-1 rounded-full font-medium"
            style="background: #fef2f2; color: #991b1b;">
        Expired
      </span>
    <% elsif @packet.expiring_soon? %>
      <span class="text-sm px-3 py-1 rounded-full font-medium"
            style="background: var(--alert-amber-bg); color: #92400e;">
        Expiring soon — sow by <%= @packet.sow_by_date.strftime("%B %-d, %Y") %>
      </span>
    <% end %>
  </div>
<% else %>
  <h1 class="text-2xl font-bold mb-5" style="color: var(--text-primary);">Add Seed Packet</h1>
<% end %>

<!-- Edit / Add Form -->
<div class="px-4 py-4 mb-4" style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow);">
  <p style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; font-weight: 600; color: var(--gray-500);" class="mb-4">
    <%= new_record ? "Packet Details" : "Edit" %>
  </p>

  <form method="post" action="<%= new_record ? '/seeds' : "/seeds/#{@packet.id}" %>"
        class="flex flex-col gap-4">
    <% unless new_record %>
      <input type="hidden" name="_method" value="PATCH">
    <% end %>

    <div>
      <label class="block text-xs font-medium mb-1" style="color: var(--gray-500);">Variety name *</label>
      <input type="text" name="variety_name" required
             value="<%= @packet.variety_name %>"
             class="w-full rounded-lg px-3 py-2.5 text-sm border"
             style="border-color: #e5e7eb; color: var(--text-primary);">
    </div>

    <div>
      <label class="block text-xs font-medium mb-1" style="color: var(--gray-500);">Crop type *</label>
      <input type="text" name="crop_type" required
             value="<%= @packet.crop_type %>"
             placeholder="e.g. tomato, herb, pepper"
             class="w-full rounded-lg px-3 py-2.5 text-sm border"
             style="border-color: #e5e7eb; color: var(--text-primary);">
    </div>

    <div>
      <label class="block text-xs font-medium mb-1" style="color: var(--gray-500);">Source</label>
      <input type="text" name="source"
             value="<%= @packet.source %>"
             placeholder="e.g. Loukykvět, saved"
             class="w-full rounded-lg px-3 py-2.5 text-sm border"
             style="border-color: #e5e7eb; color: var(--text-primary);">
    </div>

    <div>
      <label class="block text-xs font-medium mb-1" style="color: var(--gray-500);">Quantity remaining</label>
      <input type="number" name="quantity_remaining" min="-999" max="9999"
             value="<%= @packet.quantity_remaining %>"
             placeholder="Approximate count or packets"
             class="w-full rounded-lg px-3 py-2.5 text-sm border"
             style="border-color: #e5e7eb; color: var(--text-primary);">
    </div>

    <div class="grid grid-cols-2 gap-3">
      <div>
        <label class="block text-xs font-medium mb-1" style="color: var(--gray-500);">Sow by date</label>
        <input type="date" name="sow_by_date"
               value="<%= @packet.sow_by_date %>"
               class="w-full rounded-lg px-3 py-2.5 text-sm border"
               style="border-color: #e5e7eb; color: var(--text-primary);">
      </div>
      <div>
        <label class="block text-xs font-medium mb-1" style="color: var(--gray-500);">Purchase date</label>
        <input type="date" name="purchase_date"
               value="<%= @packet.purchase_date %>"
               class="w-full rounded-lg px-3 py-2.5 text-sm border"
               style="border-color: #e5e7eb; color: var(--text-primary);">
      </div>
    </div>

    <div>
      <label class="block text-xs font-medium mb-1" style="color: var(--gray-500);">Supplier URL</label>
      <input type="url" name="url"
             value="<%= @packet.url %>"
             placeholder="https://"
             class="w-full rounded-lg px-3 py-2.5 text-sm border"
             style="border-color: #e5e7eb; color: var(--text-primary);">
    </div>

    <div>
      <label class="block text-xs font-medium mb-1" style="color: var(--gray-500);">Notes</label>
      <textarea name="notes" rows="3"
                class="w-full rounded-lg px-3 py-2.5 text-sm border resize-none"
                style="border-color: #e5e7eb; color: var(--text-primary);"><%= @packet.notes %></textarea>
    </div>

    <button type="submit"
            class="w-full py-3 rounded-xl font-semibold text-sm text-white transition hover:opacity-90"
            style="background: var(--green-900);">
      <%= new_record ? "Add Packet" : "Save Changes" %>
    </button>
  </form>
</div>

<!-- Delete (existing records only) -->
<% unless new_record %>
  <form method="post" action="/seeds/<%= @packet.id %>"
        onsubmit="return confirm('Delete this seed packet?')">
    <input type="hidden" name="_method" value="DELETE">
    <button type="submit"
            class="w-full py-3 rounded-xl font-semibold text-sm transition hover:opacity-80"
            style="background: #fef2f2; color: #991b1b;">
      Delete packet
    </button>
  </form>
<% end %>
```

### 3.4 Verify views render

- [ ] Start the app and manually visit `/seeds` and `/seeds/new` in the browser:
  ```
  bundle exec ruby app.rb
  ```

### 3.5 Commit

```bash
git add views/seeds/
git commit -m "feat: add seed inventory index and show/edit views"
```

---

## Task 4 — Nav Update

### 4.1 Add Seeds tab and enable method_override

- [ ] Edit `views/layout.erb` — add the `seeds_active` variable and the Seeds tab:

  In the `<% ... %>` block just before the tab links, add:
  ```erb
  seeds_active = p.start_with?("/seeds")
  ```

  Between the Beds tab and the Succession tab, insert:
  ```erb
  <a href="/seeds" class="tab-item<%= ' active' if seeds_active %>">
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M16.5 9.4l-9-5.19"/><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/>
    </svg>
    Seeds
  </a>
  ```

  > Note: The Lucide `package` icon SVG paths above render the box/package icon matching the spec. Stroke-based, 24×24 viewBox, consistent with other tabs.

- [ ] Edit `app.rb` `configure` block — add `set :method_override, true` if not already present:
  ```ruby
  configure do
    set :views, File.join(File.dirname(__FILE__), "views")
    set :public_folder, File.join(File.dirname(__FILE__), "public")
    set :method_override, true
  end
  ```

### 4.2 Verify nav

- [ ] Visit `/seeds` in the browser — "Seeds" tab should be highlighted active.
- [ ] Visit `/` — "Home" tab active, "Seeds" tab gray (no active bleed).

### 4.3 Commit

```bash
git add views/layout.erb app.rb
git commit -m "feat: add Seeds tab to bottom nav, enable method_override"
```

---

## Task 5 — Wire Up

### 5.1 Add require to app.rb

- [ ] Edit `app.rb` — add the seeds route require after the succession line:
  ```ruby
  require_relative "routes/seeds"
  ```
  Final require block:
  ```ruby
  require_relative "routes/dashboard"
  require_relative "routes/plants"
  require_relative "routes/beds"
  require_relative "routes/tasks"
  require_relative "routes/succession"
  require_relative "routes/seeds"
  ```

### 5.2 Run full test suite

- [ ] Run all tests:
  ```
  bundle exec ruby -Itest test/routes/test_seeds.rb
  bundle exec rake test
  ```
  All tests green.

### 5.3 Smoke test in browser

- [ ] Start app: `bundle exec ruby app.rb`
- [ ] Visit `http://localhost:4567/seeds` — empty state message visible, Seeds tab active.
- [ ] Add a packet via the form — redirects to list, packet appears grouped by crop type.
- [ ] Click packet — show/edit view renders correctly.
- [ ] Edit packet — saves, redirect back to show page.
- [ ] Delete packet — removes record, redirect to list.
- [ ] Visit `http://localhost:4567/api/seeds` — returns JSON array.
- [ ] Add a packet with a past sow-by date — red "Expired" pill appears on list view.
- [ ] Add a packet with sow-by date within 6 months — amber "Sow by ..." pill appears.

### 5.4 Commit

```bash
git add app.rb
git commit -m "feat: wire seeds routes into app — seed inventory complete"
```

---

## Completion Checklist

- [ ] Migration `008_create_seed_packets.rb` runs cleanly on fresh DB
- [ ] `SeedPacket` model loads, `expired?` / `expiring_soon?` / `out_of_stock?` helpers work
- [ ] All 12 tests in `test/routes/test_seeds.rb` pass
- [ ] Full `rake test` suite still passes (no regressions)
- [ ] Seeds tab appears in nav on all pages
- [ ] `PATCH` and `DELETE` work correctly via `_method` override
- [ ] Empty state renders when no packets exist
- [ ] Sow-by warning pills render correctly (amber within 6 months, red if expired)
