require_relative "../models/task"
require_relative "../models/plant"
require_relative "../models/bed"
require_relative "../models/advisory"
require_relative "../models/stage_history"
require_relative "../services/weather_service"
require_relative "../services/sensor_service"

class GardenApp
  get "/" do
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

    # Sensor data — only fetch if at least one entity is configured
    if sensor_vars_configured?
      @sensor_zones    = SensorService.fetch_zones
      @sensor_temp     = SensorService.fetch_indoor_temp
      @sensor_rain     = SensorService.rain_detected?
      @sensors_present = true
    else
      @sensors_present = false
    end

    @germination_count = @germination_watch.count
    @upcoming_count = @upcoming_tasks.count
    @today_count = @today_tasks.count

    erb :dashboard
  end

  private

  def sensor_vars_configured?
    !ENV.fetch("HA_HYDRAWISE_ZONES", "").empty? ||
      !ENV.fetch("HA_INDOOR_TEMP_ENTITY", "").empty?
  end
end
