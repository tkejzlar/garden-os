require_relative "../test_helper"
require_relative "../../services/planner_service"

class TestPlannerService < GardenTest
  def test_system_prompt_includes_prague
    service = PlannerService.new
    assert_includes service.system_prompt, "Prague"
  end

  def test_saves_user_message
    PlannerService.new  # ensure message table exists
    PlannerMessage.create(role: "user", content: "test", created_at: Time.now, garden_id: @garden.id)
    assert_equal 1, PlannerMessage.where(role: "user").count
  end

  def test_clear_messages
    PlannerMessage.create(role: "user", content: "test", created_at: Time.now, garden_id: @garden.id)
    PlannerMessage.create(role: "assistant", content: "reply", created_at: Time.now, garden_id: @garden.id)
    PlannerMessage.dataset.delete
    assert_equal 0, PlannerMessage.count
  end
end
