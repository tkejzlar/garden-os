# test/routes/test_health.rb
require_relative "../test_helper"
require_relative "../../app"

class TestHealth < GardenTest
  def test_health_endpoint
    get "/health"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "ok"
  end
end
