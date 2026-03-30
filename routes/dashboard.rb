require_relative "../models/task"
require_relative "../models/plant"
require_relative "../models/bed"
require_relative "../models/advisory"
require_relative "../models/stage_history"
require_relative "../services/weather_service"
require_relative "../services/sensor_service"

class GardenApp
  # Dashboard page route removed — React SPA serves /

  get "/api/dashboard" do
    @today_tasks = Task.where(garden_id: @current_garden.id, due_date: Date.today)
                       .exclude(status: "done")
                       .order(:priority).all

    @upcoming_tasks = Task.where(garden_id: @current_garden.id, due_date: (Date.today + 1)..(Date.today + 7))
                          .exclude(status: "done")
                          .order(:due_date).all

    @germination_watch = Plant.where(garden_id: @current_garden.id, lifecycle_stage: %w[germinating sown_indoor])
                              .all

    @advisories = Advisory.where(garden_id: @current_garden.id, date: Date.today).all

    @weather = WeatherService.fetch_current

    sensors = {}
    if sensor_vars_configured?
      sensors[:zones]    = SensorService.fetch_zones
      sensors[:temp]     = SensorService.fetch_indoor_temp
      sensors[:rain]     = SensorService.rain_detected?
      sensors[:present]  = true
    else
      sensors[:present] = false
    end

    json({
      today_tasks:        @today_tasks.map(&:values),
      upcoming_tasks:     @upcoming_tasks.map(&:values),
      germination_watch:  @germination_watch.map(&:values),
      advisories:         @advisories.map(&:values),
      weather:            @weather,
      sensors:            sensors,
      germination_count:  @germination_watch.count,
      upcoming_count:     @upcoming_tasks.count,
      today_count:        @today_tasks.count
    })
  end

  get "/api/feature-requests" do
    gaps_dir = File.join(settings.root, "docs", "gaps")
    unless File.directory?(gaps_dir)
      return json([])
    end

    require "yaml"
    requests = Dir.glob(File.join(gaps_dir, "*-feature-request.yml")).map do |f|
      data = YAML.safe_load(File.read(f))
      data["file"] = File.basename(f)
      data
    end.sort_by { |r| r["timestamp"] || "" }.reverse

    # Filter by status (default: show only open)
    unless params[:status] == "all"
      requests = requests.select { |r| r["status"] != "resolved" }
    end

    json(requests)
  end

  patch "/api/feature-requests/:file/resolve" do
    gaps_dir = File.join(settings.root, "docs", "gaps")
    filepath = File.join(gaps_dir, params[:file])
    halt 404, json(error: "Not found") unless File.exist?(filepath)

    require "yaml"
    data = YAML.safe_load(File.read(filepath))
    data["status"] = "resolved"
    data["resolved_at"] = Time.now.iso8601
    File.write(filepath, YAML.dump(data))
    json(ok: true, file: params[:file])
  end

  delete "/api/feature-requests/duplicates" do
    gaps_dir = File.join(settings.root, "docs", "gaps")
    unless File.directory?(gaps_dir)
      return json(removed: 0)
    end

    require "yaml"
    files = Dir.glob(File.join(gaps_dir, "*-feature-request.yml"))
    seen = {}
    removed = 0

    files.sort.reverse.each do |f|
      data = YAML.safe_load(File.read(f))
      key = data["summary"].to_s.downcase.strip
      if seen[key]
        File.delete(f)
        removed += 1
      else
        seen[key] = f
      end
    end

    json(removed: removed)
  end

  private

  def sensor_vars_configured?
    !ENV.fetch("HA_HYDRAWISE_ZONES", "").empty? ||
      !ENV.fetch("HA_INDOOR_TEMP_ENTITY", "").empty?
  end
end
