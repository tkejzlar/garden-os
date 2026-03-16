require_relative "../test_helper"
require_relative "../../app"

class TestTasks < GardenTest
  def test_complete_task
    task = Task.create(title: "Sow lettuce", task_type: "sow",
                       due_date: Date.today, status: "upcoming")
    post "/tasks/#{task.id}/complete"
    assert_equal 302, last_response.status
    assert_equal "done", task.reload.status
  end

  def test_api_tasks
    Task.create(title: "Water beds", task_type: "water",
                due_date: Date.today, status: "upcoming")
    get "/api/tasks"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 1, data.length
  end
end
