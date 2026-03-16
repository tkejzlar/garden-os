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

  get "/health" do
    json status: "ok"
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
end
