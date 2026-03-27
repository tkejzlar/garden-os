# app.rb
require "sinatra/base"
require "sinatra/json"
require_relative "config/database"

class GardenApp < Sinatra::Base
  helpers Sinatra::JSON

  configure do
    set :views, File.join(File.dirname(__FILE__), "views")
    set :public_folder, File.join(File.dirname(__FILE__), "public")
    set :method_override, true
    enable :static
  end

  configure :development do
    require "sinatra/reloader"
    register Sinatra::Reloader
    also_reload "routes/*.rb"
    also_reload "models/*.rb"
    also_reload "services/*.rb"
  end

  # ── CORS for Vite dev server ──────────────────────────────────────────
  before do
    if settings.development?
      headers 'Access-Control-Allow-Origin' => '*',
              'Access-Control-Allow-Methods' => 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
              'Access-Control-Allow-Headers' => 'Content-Type'
    end
  end

  options '*' do
    200
  end

  before do
    require_relative "models/garden"
    garden_id = request.cookies["garden_id"]&.to_i
    @current_garden = (garden_id && Garden[garden_id]) || Garden.first
    @gardens = Garden.order(:name).all
  end

  post "/gardens/switch/:id" do
    require_relative "models/garden"
    garden = Garden[params[:id].to_i]
    halt 404 unless garden
    response.set_cookie("garden_id", value: garden.id.to_s, path: "/", httponly: true, same_site: :lax)
    if request.accept?('application/json')
      json(ok: true, garden_id: garden.id)
    else
      redirect back
    end
  end

  get "/api/gardens" do
    json({
      current_id: @current_garden.id,
      gardens: @gardens.map { |g| { id: g.id, name: g.name } }
    })
  end

  post "/api/gardens/switch/:id" do
    require_relative "models/garden"
    garden = Garden[params[:id].to_i]
    halt 404 unless garden
    response.set_cookie("garden_id", value: garden.id.to_s, path: "/", httponly: true, same_site: :lax)
    json(ok: true, garden_id: garden.id)
  end

  get "/health" do
    json status: "ok"
  end

  # ── Garden Journal/Quick Log ──
  get "/api/journal" do
    require_relative "models/garden_log"
    logs = GardenLog.where(garden_id: @current_garden.id).order(Sequel.desc(:created_at)).limit(50).all
    json logs.map(&:values)
  end

  post "/api/journal" do
    require_relative "models/garden_log"
    request.body.rewind
    body = begin JSON.parse(request.body.read) rescue {} end
    log = GardenLog.create(
      garden_id: @current_garden.id,
      log_type: body["type"] || "note",
      note: body["note"],
      created_at: Time.now
    )
    status 201
    json log.values
  end

  # ── Tasks JSON API ──
  get "/api/tasks" do
    require_relative "models/task"
    tasks = Task.where(garden_id: @current_garden.id).exclude(status: "done").order(:due_date).all
    json tasks.map { |t|
      bed_names = (t.respond_to?(:bed_names) ? t.bed_names : nil) || []
      { id: t.id, title: t.title, due_date: t.due_date&.to_s, status: t.status, priority: t.priority || "normal", bed_names: bed_names }
    }
  end

  post "/api/tasks/:id/complete" do
    require_relative "models/task"
    task = Task[params[:id].to_i]
    halt 404 unless task
    task.update(status: "done", completed_at: Time.now)
    json(ok: true)
  end

  not_found do
    @title = "Not Found"
    erb :error, locals: { code: 404, message: "Page not found" }
  end

  error do
    @title = "Error"
    erb :error, locals: { code: 500, message: "Something went wrong" }
  end

end

require_relative "routes/dashboard"
require_relative "routes/plants"
require_relative "routes/beds"
require_relative "routes/tasks"
require_relative "routes/succession"
require_relative "routes/seeds"
require_relative "routes/photos"

# JSON API endpoint combining all data for HACS
class GardenApp
  get "/api/status" do
    json(
      plants: Plant.exclude(lifecycle_stage: "done").count,
      tasks_today: Task.where(due_date: Date.today).exclude(status: "done").count,
      germinating: Plant.where(lifecycle_stage: "germinating").count
    )
  end

  # ── Serve SPA static assets from dist/ ──
  # Hashed assets get immutable caching
  get "/assets/*" do
    asset_path = File.join(File.dirname(__FILE__), "dist", "assets", params[:splat].first)
    if File.exist?(asset_path)
      headers "Cache-Control" => "public, max-age=31536000, immutable"
      send_file asset_path
    else
      halt 404
    end
  end

  # ── SPA catch-all: serve React app for non-API routes ──
  get "/*" do
    spa_index = File.join(File.dirname(__FILE__), "dist", "index.html")
    if File.exist?(spa_index) && !request.path_info.start_with?("/api/")
      headers "Cache-Control" => "public, max-age=0, must-revalidate"
      send_file spa_index
    else
      halt 404
    end
  end
end
