# app.rb
require "sinatra/base"
require "sinatra/json"
require_relative "config/database"

class GardenApp < Sinatra::Base
  helpers Sinatra::JSON

  configure do
    set :views, File.join(File.dirname(__FILE__), "views")
    set :public_folder, File.join(File.dirname(__FILE__), "public")
  end

  get "/health" do
    json status: "ok"
  end
end

require_relative "routes/dashboard"
require_relative "routes/plants"
