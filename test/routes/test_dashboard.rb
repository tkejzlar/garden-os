require_relative "../test_helper"
require_relative "../../app"

class TestDashboard < GardenTest
  def test_dashboard_renders
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "GardenOS"
  end

  def test_dashboard_shows_todays_tasks
    Task.create(title: "Sow lettuce", task_type: "sow",
                due_date: Date.today, status: "upcoming")
    get "/"
    assert_includes last_response.body, "Sow lettuce"
  end

  def test_dashboard_shows_germination_watch
    station = IndoorStation.create(name: "Heat mat", station_type: "heat_mat")
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato",
                         lifecycle_stage: "germinating",
                         indoor_station_id: station.id,
                         sow_date: Date.today - 5)
    StageHistory.create(plant_id: plant.id, to_stage: "germinating",
                        changed_at: Time.now - (5 * 86400))
    get "/"
    assert_includes last_response.body, "Raf"
  end
end
