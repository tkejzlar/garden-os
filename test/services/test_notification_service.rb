require_relative "../test_helper"
require_relative "../../services/notification_service"

class TestNotificationService < GardenTest
  def test_builds_morning_brief_payload
    payload = NotificationService.morning_brief_payload(
      task_count: 3,
      weather_summary: "Sunny, 18C",
      germination_alerts: "Peppers day 5 on heat mat",
      dashboard_url: "http://garden.local:4567"
    )

    assert_equal "Garden — #{Date.today}", payload[:title]
    assert_includes payload[:message], "3 tasks today"
    assert_includes payload[:message], "Sunny, 18C"
  end

  def test_builds_frost_alert_payload
    payload = NotificationService.frost_alert_payload(
      min_temp: -2,
      when_str: "tonight",
      tender_count: 5
    )

    assert_includes payload[:title], "Frost"
    assert_includes payload[:message], "-2"
    assert_includes payload[:message], "5 tender"
  end
end
