require_relative "../models/task"
require_relative "../models/plant"
require_relative "../models/bed"
require_relative "../models/advisory"
require_relative "../models/stage_history"
require_relative "../services/weather_service"

class GardenApp
  get "/" do
    @today_tasks = Task.where(due_date: Date.today)
                       .exclude(status: "done")
                       .order(:priority).all

    @upcoming_tasks = Task.where(due_date: (Date.today + 1)..(Date.today + 7))
                          .exclude(status: "done")
                          .order(:due_date).all

    @germination_watch = Plant.where(lifecycle_stage: %w[germinating sown_indoor])
                              .all

    @advisories = Advisory.where(date: Date.today).all

    @weather = WeatherService.fetch_current

    @germination_count = @germination_watch.count
    @upcoming_count = @upcoming_tasks.count
    @today_count = @today_tasks.count

    erb :dashboard
  end
end
