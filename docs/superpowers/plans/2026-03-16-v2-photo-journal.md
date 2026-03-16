# Photo Journal Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add photo upload, storage, and display to the plant detail page so each plant builds a visual timeline of its growth.
**Architecture:** Photos are stored on disk under `public/uploads/YYYY/MM/` with optional 200px thumbnails generated via ImageMagick; a `photos` table records metadata. Routes follow the existing Sinatra pattern in `routes/plants.rb`; the plant detail page gains a camera button that expands an upload form, and photos appear as thumbnail cards interleaved in the timeline.
**Tech Stack:** Sinatra multipart upload, Sequel/SQLite, ImageMagick (`convert`) via `system()` call, Rack::Test for integration tests, ERB with existing Tailwind/CSS variables.
**Spec:** `docs/superpowers/specs/2026-03-16-v2-features.md` — Section 2

---

## Step 1 — Migration: create `photos` table

- [ ] Create `db/migrations/009_create_photos.rb`:

```ruby
Sequel.migration do
  change do
    create_table(:photos) do
      primary_key :id
      foreign_key :plant_id, :plants, on_delete: :set_null
      foreign_key :bed_id, :beds, on_delete: :set_null
      String :lifecycle_stage
      String :filename, null: false
      Text   :caption
      DateTime :taken_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      index :plant_id
      index :bed_id
    end
  end
end
```

- [ ] Run migration against development DB:

```bash
bundle exec rake db:migrate
```

- [ ] Confirm the test DB also picks it up automatically (the test helper runs `Sequel::Migrator.run` on every test run — no extra step needed).

---

## Step 2 — Model: `models/photo.rb`

- [ ] Create `models/photo.rb`:

```ruby
require_relative "../config/database"

class Photo < Sequel::Model
  many_to_one :plant
  many_to_one :bed

  UPLOAD_ROOT = File.expand_path("../public/uploads", __dir__).freeze
  MAX_BYTES   = 10 * 1024 * 1024  # 10 MB

  # Absolute path to the original file on disk.
  def file_path
    File.join(UPLOAD_ROOT, filename)
  end

  # Absolute path to the thumbnail (200px-wide), or nil if it does not exist.
  def thumbnail_path
    thumb = file_path.sub(/(\.\w+)$/, "_thumb\\1")
    File.exist?(thumb) ? thumb : nil
  end

  # Web-accessible URL path for use in src= attributes.
  def url
    "/uploads/#{filename}"
  end

  # Web-accessible URL path for the thumbnail, falling back to the original.
  def thumbnail_url
    thumb_file = file_path.sub(/(\.\w+)$/, "_thumb\\1")
    if File.exist?(thumb_file)
      "/uploads/#{filename.sub(/(\.\w+)$/, '_thumb\\1')}"
    else
      url
    end
  end

  # Generate a thumbnail with ImageMagick. Silently skips if `convert` is
  # unavailable or the conversion fails.
  def generate_thumbnail!
    thumb = file_path.sub(/(\.\w+)$/, "_thumb\\1")
    system("convert", "-resize", "200x", file_path, thumb)
  end

  # Delete the file (and thumbnail if present) from disk. Call before
  # destroying the record.
  def delete_files!
    File.delete(file_path) if File.exist?(file_path)
    thumb = file_path.sub(/(\.\w+)$/, "_thumb\\1")
    File.delete(thumb) if File.exist?(thumb)
  end

  # Build a datestamped relative storage path, e.g. "2026/03/abc123.jpg".
  # The caller is responsible for ensuring the directory exists.
  def self.storage_path(original_filename)
    now = Time.now
    ext = File.extname(original_filename).downcase
    basename = "#{now.to_i}_#{SecureRandom.hex(6)}#{ext}"
    File.join(now.strftime("%Y"), now.strftime("%m"), basename)
  end
end
```

- [ ] Add `one_to_many :photos` association to `models/plant.rb` (append after the existing `one_to_many :stage_histories` line):

```ruby
one_to_many :photos
```

- [ ] Add `require_relative "../models/photo"` to the top of the photo routes file (Step 3).

---

## Step 3 — Routes: `routes/photos.rb`

- [ ] Create `routes/photos.rb`:

```ruby
require "securerandom"
require_relative "../models/plant"
require_relative "../models/photo"

class GardenApp
  # POST /plants/:id/photos — multipart file upload
  post "/plants/:id/photos" do
    plant = Plant[params[:id].to_i]
    halt 404, "Plant not found" unless plant

    upload = params[:photo]
    halt 400, "No file provided" unless upload && upload[:tempfile]

    # Enforce 10 MB limit
    tempfile = upload[:tempfile]
    tempfile.seek(0, IO::SEEK_END)
    halt 413, "File too large (max 10 MB)" if tempfile.pos > Photo::MAX_BYTES
    tempfile.rewind

    rel_path  = Photo.storage_path(upload[:filename])
    full_path = File.join(Photo::UPLOAD_ROOT, rel_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.open(full_path, "wb") { |f| f.write(tempfile.read) }

    photo = Photo.create(
      plant_id:        plant.id,
      lifecycle_stage: plant.lifecycle_stage,
      filename:        rel_path,
      caption:         params[:caption].to_s.strip.then { |s| s.empty? ? nil : s },
      taken_at:        Time.now
    )
    photo.generate_thumbnail!

    redirect "/plants/#{plant.id}"
  end

  # GET /plants/:id/photos — full photo gallery for a plant
  get "/plants/:id/photos" do
    @plant  = Plant[params[:id].to_i]
    halt 404, "Plant not found" unless @plant
    @photos = Photo.where(plant_id: @plant.id).order(Sequel.desc(:taken_at)).all
    erb :"plants/photos"
  end

  # DELETE /photos/:id — delete record and file
  delete "/photos/:id" do
    photo = Photo[params[:id].to_i]
    halt 404, "Photo not found" unless photo
    plant_id = photo.plant_id
    photo.delete_files!
    photo.destroy
    redirect plant_id ? "/plants/#{plant_id}" : "/"
  end
end
```

- [ ] Register the new route file in `app.rb` (add after the existing route requires):

```ruby
require_relative "routes/photos"
```

- [ ] Ensure Sinatra multipart is enabled. In `app.rb` inside the `configure` block, add:

```ruby
enable :static
```

  (Already implied by `:public_folder` being set. No extra gem needed — Rack handles multipart by default with Sinatra.)

---

## Step 4 — Update `views/plants/show.erb`

Four changes to the existing file:

### 4a — Load `@photos` in the show route

The show route in `routes/plants.rb` needs `@photos` populated. Edit `routes/plants.rb`, replacing:

```ruby
  get "/plants/:id" do
    @plant = Plant[params[:id].to_i]
    halt 404, "Plant not found" unless @plant
    @history = StageHistory.where(plant_id: @plant.id).order(:changed_at).all
    erb :"plants/show"
  end
```

with:

```ruby
  get "/plants/:id" do
    @plant = Plant[params[:id].to_i]
    halt 404, "Plant not found" unless @plant
    @history = StageHistory.where(plant_id: @plant.id).order(:changed_at).all
    @photos  = Photo.where(plant_id: @plant.id).order(Sequel.desc(:taken_at)).all
    erb :"plants/show"
  end
```

Also add `require_relative "../models/photo"` at the top of `routes/plants.rb`.

### 4b — Camera button + upload form

Insert the following block directly after the closing `</div>` of the Actions Card (after line 46 — the `<% end %>` that closes the `next_stages` block and the card `</div>`):

```erb
<!-- Photo Upload Card -->
<div class="mb-4 px-4 py-4" style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow);"
     x-data="{ open: false }">
  <div class="flex items-center justify-between">
    <p style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; font-weight: 600; color: var(--gray-500);">
      Photos
    </p>
    <button @click="open = !open"
            class="flex items-center gap-1 px-3 py-1 text-sm font-medium rounded-lg transition hover:opacity-80"
            style="background: var(--green-900); color: white;">
      <!-- Lucide camera icon (inline SVG, 16px) -->
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
           fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3L14.5 4z"/>
        <circle cx="12" cy="13" r="3"/>
      </svg>
      Add Photo
    </button>
  </div>

  <!-- Expandable upload form -->
  <div x-show="open" x-transition class="mt-3">
    <form method="post" action="/plants/<%= @plant.id %>/photos" enctype="multipart/form-data"
          class="flex flex-col gap-3">
      <input type="file" name="photo" accept="image/*" capture="environment" required
             class="text-sm" style="color: var(--text-primary);">
      <input type="text" name="caption" placeholder="Caption (optional)"
             class="w-full px-3 py-2 text-sm rounded-lg border"
             style="border-color: #e5e7eb; color: var(--text-primary);">
      <button type="submit"
              class="w-full px-4 py-2 text-sm font-medium rounded-xl transition hover:opacity-90"
              style="background: var(--green-900); color: white;">
        Upload
      </button>
    </form>
  </div>
</div>
```

### 4c — Photo thumbnails strip

Insert the following block after the Photo Upload Card (still before the Timeline Card):

```erb
<!-- Recent Photos Strip -->
<% unless @photos.empty? %>
  <div class="mb-4 px-4 py-4" style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow);">
    <div class="flex items-center justify-between mb-3">
      <p style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; font-weight: 600; color: var(--gray-500);">
        Recent Photos
      </p>
      <a href="/plants/<%= @plant.id %>/photos"
         class="text-xs font-medium hover:underline" style="color: var(--green-900);">
        View all (<%= @photos.size %>)
      </a>
    </div>
    <div class="flex gap-2 overflow-x-auto pb-1">
      <% @photos.first(6).each do |photo| %>
        <div class="relative flex-shrink-0" style="width: 80px;">
          <a href="/plants/<%= @plant.id %>/photos">
            <img src="<%= photo.thumbnail_url %>" alt="<%= photo.caption || 'Plant photo' %>"
                 style="width: 80px; height: 80px; object-fit: cover; border-radius: 8px;">
          </a>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

### 4d — Photo entries in the timeline

Inside the existing Timeline Card, replace the `@history.each` block (lines 90–109 of the original `show.erb`) so that stage-history entries and photos are interleaved chronologically:

```erb
  <% if @history.empty? && @photos.empty? %>
    <p class="text-sm" style="color: var(--text-secondary);">No history yet.</p>
  <% else %>
    <%
      # Merge stage history and photos into one sorted list, newest last.
      timeline_items = []
      @history.each { |h| timeline_items << { type: :stage, at: h.changed_at, data: h } }
      @photos.each  { |p| timeline_items << { type: :photo, at: p.taken_at,   data: p } }
      timeline_items.sort_by! { |item| item[:at] }
    %>
    <ol class="relative" style="border-left: 2px solid #86efac; margin-left: 8px; padding-left: 0;">
      <% timeline_items.each do |item| %>
        <% if item[:type] == :stage %>
          <% h = item[:data] %>
          <li class="relative pb-4 last:pb-0" style="padding-left: 20px;">
            <div class="absolute rounded-full"
                 style="width: 10px; height: 10px; background: #16a34a; border: 2px solid white; left: -6px; top: 4px; box-shadow: 0 0 0 1px #16a34a;">
            </div>
            <p class="text-sm font-semibold" style="color: var(--text-primary);">
              <%= h.to_stage.tr('_', ' ').capitalize %>
            </p>
            <p class="text-xs mt-0.5" style="color: var(--text-secondary);">
              <%= h.changed_at.strftime("%b %-d, %Y %H:%M") %>
            </p>
            <% if h.note %>
              <p class="text-xs mt-1" style="color: var(--text-body);"><%= h.note %></p>
            <% end %>
          </li>
        <% else %>
          <% photo = item[:data] %>
          <li class="relative pb-4 last:pb-0" style="padding-left: 20px;">
            <!-- Camera dot -->
            <div class="absolute rounded-full flex items-center justify-center"
                 style="width: 10px; height: 10px; background: #0ea5e9; border: 2px solid white; left: -6px; top: 4px; box-shadow: 0 0 0 1px #0ea5e9;">
            </div>
            <div class="flex items-start gap-2">
              <a href="/plants/<%= @plant.id %>/photos">
                <img src="<%= photo.thumbnail_url %>" alt=""
                     style="width: 56px; height: 56px; object-fit: cover; border-radius: 6px; flex-shrink: 0;">
              </a>
              <div class="flex-1 min-w-0">
                <p class="text-xs mt-0.5" style="color: var(--text-secondary);">
                  <%= photo.taken_at.strftime("%b %-d, %Y %H:%M") %>
                  <% if photo.lifecycle_stage %>
                    &middot; <%= photo.lifecycle_stage.tr('_', ' ') %>
                  <% end %>
                </p>
                <% if photo.caption %>
                  <p class="text-xs mt-0.5" style="color: var(--text-body);"><%= photo.caption %></p>
                <% end %>
              </div>
              <form method="post" action="/photos/<%= photo.id %>"
                    onsubmit="return confirm('Delete this photo?')">
                <input type="hidden" name="_method" value="DELETE">
                <button type="submit" class="text-xs hover:opacity-70" style="color: #ef4444;">
                  &times;
                </button>
              </form>
            </div>
          </li>
        <% end %>
      <% end %>
    </ol>
  <% end %>
```

Note: The `_method` override for DELETE requires Sinatra's method override to be enabled. Add the following to the `configure` block in `app.rb` if not already present:

```ruby
enable :method_override
```

---

## Step 5 — Gallery view: `views/plants/photos.erb`

- [ ] Create `views/plants/photos.erb`:

```erb
<!-- Back Link -->
<a href="/plants/<%= @plant.id %>" class="text-sm hover:underline mb-5 inline-block" style="color: var(--green-900);">
  &larr; <%= @plant.variety_name %>
</a>

<!-- Page Header -->
<div class="mb-5">
  <h1 class="text-2xl font-bold" style="color: var(--text-primary); letter-spacing: -0.5px;">
    Photos
  </h1>
  <p class="text-sm mt-1" style="color: var(--text-secondary);">
    <%= @plant.variety_name %> &mdash; <%= @plant.crop_type %>
  </p>
</div>

<!-- Upload Form -->
<div class="mb-5 px-4 py-4" style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow);"
     x-data="{ open: false }">
  <button @click="open = !open"
          class="flex items-center gap-2 text-sm font-medium"
          style="color: var(--green-900);">
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
         fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3L14.5 4z"/>
      <circle cx="12" cy="13" r="3"/>
    </svg>
    Add another photo
  </button>
  <div x-show="open" x-transition class="mt-3">
    <form method="post" action="/plants/<%= @plant.id %>/photos" enctype="multipart/form-data"
          class="flex flex-col gap-3">
      <input type="file" name="photo" accept="image/*" capture="environment" required
             class="text-sm" style="color: var(--text-primary);">
      <input type="text" name="caption" placeholder="Caption (optional)"
             class="w-full px-3 py-2 text-sm rounded-lg border"
             style="border-color: #e5e7eb; color: var(--text-primary);">
      <button type="submit"
              class="w-full px-4 py-2 text-sm font-medium rounded-xl transition hover:opacity-90"
              style="background: var(--green-900); color: white;">
        Upload
      </button>
    </form>
  </div>
</div>

<!-- Photo Grid / Empty State -->
<% if @photos.empty? %>
  <div class="px-4 py-8 text-center" style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow);">
    <p class="text-sm" style="color: var(--text-secondary);">No photos yet. Tap the camera icon to add one.</p>
  </div>
<% else %>
  <div class="grid grid-cols-2 gap-3">
    <% @photos.each do |photo| %>
      <div style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow); overflow: hidden;">
        <img src="<%= photo.thumbnail_url %>"
             alt="<%= photo.caption || 'Plant photo' %>"
             style="width: 100%; aspect-ratio: 1 / 1; object-fit: cover; display: block;">
        <div class="px-3 py-2">
          <% if photo.caption %>
            <p class="text-xs font-medium truncate" style="color: var(--text-primary);">
              <%= photo.caption %>
            </p>
          <% end %>
          <p class="text-xs mt-0.5" style="color: var(--text-secondary);">
            <%= photo.taken_at.strftime("%b %-d, %Y") %>
            <% if photo.lifecycle_stage %>
              &middot; <%= photo.lifecycle_stage.tr('_', ' ') %>
            <% end %>
          </p>
          <form method="post" action="/photos/<%= photo.id %>"
                class="mt-1" onsubmit="return confirm('Delete this photo?')">
            <input type="hidden" name="_method" value="DELETE">
            <button type="submit" class="text-xs hover:underline" style="color: #ef4444;">
              Delete
            </button>
          </form>
        </div>
      </div>
    <% end %>
  </div>
<% end %>
```

---

## Step 6 — Tests: `test/routes/test_photos.rb`

- [ ] Create `test/routes/test_photos.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../app"
require "tempfile"

class TestPhotos < GardenTest
  def setup
    super
    @plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seedling")
    # Point upload root to a temp directory so tests never touch public/
    @tmp_dir = Dir.mktmpdir("garden_photos_test")
    Photo.send(:remove_const, :UPLOAD_ROOT) rescue nil
    Photo.const_set(:UPLOAD_ROOT, @tmp_dir)
  end

  def teardown
    FileUtils.remove_entry(@tmp_dir) if File.exist?(@tmp_dir)
  end

  # --- Upload ---

  def test_upload_photo_redirects_to_plant
    post "/plants/#{@plant.id}/photos", photo_params("test.jpg")
    assert_equal 302, last_response.status
    assert_includes last_response.headers["Location"], "/plants/#{@plant.id}"
  end

  def test_upload_creates_db_record
    post "/plants/#{@plant.id}/photos", photo_params("test.jpg")
    assert_equal 1, Photo.count
    photo = Photo.first
    assert_equal @plant.id,          photo.plant_id
    assert_equal "seedling",         photo.lifecycle_stage
    assert_match /\.jpg$/,           photo.filename
  end

  def test_upload_saves_file_to_disk
    post "/plants/#{@plant.id}/photos", photo_params("test.jpg")
    photo = Photo.first
    assert File.exist?(photo.file_path), "Expected file at #{photo.file_path}"
  end

  def test_upload_with_caption
    post "/plants/#{@plant.id}/photos", photo_params("test.jpg").merge(caption: "First leaf!")
    assert_equal "First leaf!", Photo.first.caption
  end

  def test_upload_rejects_missing_file
    post "/plants/#{@plant.id}/photos", {}
    assert_equal 400, last_response.status
  end

  def test_upload_rejects_oversized_file
    # Build a 1-byte-over-limit tempfile
    oversized = Tempfile.new(["big", ".jpg"])
    oversized.write("x" * (Photo::MAX_BYTES + 1))
    oversized.rewind
    params = { photo: { filename: "big.jpg", type: "image/jpeg", tempfile: oversized } }
    post "/plants/#{@plant.id}/photos", params
    assert_equal 413, last_response.status
  ensure
    oversized&.close!
  end

  def test_upload_returns_404_for_unknown_plant
    post "/plants/99999/photos", photo_params("test.jpg")
    assert_equal 404, last_response.status
  end

  # --- Gallery page ---

  def test_gallery_page_renders
    get "/plants/#{@plant.id}/photos"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "No photos yet"
  end

  def test_gallery_page_lists_photos
    post "/plants/#{@plant.id}/photos", photo_params("a.jpg").merge(caption: "Day one")
    get "/plants/#{@plant.id}/photos"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Day one"
  end

  # --- Delete ---

  def test_delete_removes_record
    post "/plants/#{@plant.id}/photos", photo_params("del.jpg")
    photo = Photo.first
    delete "/photos/#{photo.id}"
    assert_equal 0, Photo.count
  end

  def test_delete_removes_file_from_disk
    post "/plants/#{@plant.id}/photos", photo_params("del.jpg")
    photo = Photo.first
    path = photo.file_path
    assert File.exist?(path)
    delete "/photos/#{photo.id}"
    refute File.exist?(path)
  end

  def test_delete_redirects_to_plant
    post "/plants/#{@plant.id}/photos", photo_params("del.jpg")
    photo = Photo.first
    delete "/photos/#{photo.id}"
    assert_equal 302, last_response.status
    assert_includes last_response.headers["Location"], "/plants/#{@plant.id}"
  end

  def test_delete_returns_404_for_unknown_photo
    delete "/photos/99999"
    assert_equal 404, last_response.status
  end

  # --- Plant show page includes photos ---

  def test_plant_show_includes_photo_thumbnails
    post "/plants/#{@plant.id}/photos", photo_params("vis.jpg").merge(caption: "Visible")
    get "/plants/#{@plant.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Visible"
  end

  private

  def photo_params(filename)
    tf = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    tf.write("\xff\xd8\xff\xe0" + "fake jpeg data")  # minimal JPEG magic bytes
    tf.rewind
    # Store tempfile reference so GC doesn't close it before Rack reads it
    @tempfiles ||= []
    @tempfiles << tf
    { photo: { filename: filename, type: "image/jpeg", tempfile: tf } }
  end
end
```

- [ ] Run tests:

```bash
bundle exec ruby -Itest test/routes/test_photos.rb
```

- [ ] Run full suite to confirm no regressions:

```bash
bundle exec rake test
```

---

## Step 7 — Ensure `public/uploads` exists and is gitignored

- [ ] Create the uploads directory with a `.gitkeep`:

```bash
mkdir -p public/uploads
touch public/uploads/.gitkeep
```

- [ ] Add to `.gitignore` (append):

```
public/uploads/**/*
!public/uploads/.gitkeep
```

---

## Step 8 — Commit

- [ ] Stage and commit:

```bash
git add db/migrations/009_create_photos.rb \
        models/photo.rb \
        models/plant.rb \
        routes/photos.rb \
        routes/plants.rb \
        app.rb \
        views/plants/show.erb \
        views/plants/photos.erb \
        test/routes/test_photos.rb \
        public/uploads/.gitkeep \
        .gitignore

git commit -m "feat: add Photo Journal — upload, thumbnails, plant timeline"
```

---

## Implementation Notes

**Alpine.js dependency:** The upload forms use `x-data`/`x-show`/`@click`. Alpine.js must already be loaded in the layout. If it is not, add the CDN script tag to `views/layout.erb` (or equivalent):

```html
<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
```

**ImageMagick:** The `generate_thumbnail!` method calls `convert` via `system()`. If ImageMagick is not installed, `system()` returns `false`/`nil` and the original image is served instead — no error is raised and no fallback code is needed. Thumbnails are a progressive enhancement.

**Migration number:** Migrations 007 and 008 are assumed to exist (e.g., for the Harvest Log feature, which is recommended to be built first per the spec's build order). If photos is built before harvest, renumber to `007_create_photos.rb` and adjust accordingly.

**`bed_id` column:** The column is created for future use (spec note: "no route to populate it for now"). The upload route only sets `plant_id`; `bed_id` remains NULL.

**File size check:** The check reads to `IO::SEEK_END` and checks `pos`. This works correctly with Rack's `Tempfile`-backed uploads. Alternative: check `tempfile.size` (equivalent on most systems).
