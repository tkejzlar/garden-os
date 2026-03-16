require "json"
require "httpx"
require_relative "../models/task"
require_relative "../models/plant"
require_relative "weather_service"

class NotificationService
  def self.ha_url         = ENV.fetch("HA_URL", "http://homeassistant.local:8123")
  def self.ha_token       = ENV.fetch("HA_TOKEN", "")
  def self.notify_service = ENV.fetch("HA_NOTIFY_SERVICE", "notify.mobile_app_toms_phone")

  def self.send!(title:, message:, data: {})
    return false if ha_token.empty?

    payload = {
      title: title,
      message: message,
      data: data
    }

    response = HTTPX.with(
      headers: {
        "Authorization" => "Bearer #{ha_token}",
        "Content-Type" => "application/json"
      }
    ).post(
      "#{ha_url}/api/services/#{notify_service.sub('.', '/')}",
      json: payload
    )

    response.status == 200
  rescue => e
    warn "NotificationService error: #{e.message}"
    false
  end

  def self.morning_brief_payload(task_count:, weather_summary:, germination_alerts:, dashboard_url:)
    {
      title: "Garden — #{Date.today}",
      message: [
        "#{task_count} tasks today.",
        weather_summary,
        germination_alerts
      ].compact.reject(&:empty?).join("\n"),
      data: { url: dashboard_url }
    }
  end

  def self.frost_alert_payload(min_temp:, when_str:, tender_count:)
    {
      title: "Frost warning",
      message: "#{min_temp}C expected #{when_str}. #{tender_count} tender plants outside.",
      data: {
        actions: [
          { action: "FROST_ACKNOWLEDGE", title: "Got it" }
        ]
      }
    }
  end

  def self.send_morning_brief!
    tasks = Task.where(due_date: Date.today).exclude(status: "done").all
    weather = WeatherService.fetch_current
    germ_plants = Plant.where(lifecycle_stage: %w[germinating sown_indoor]).all

    weather_str = weather ? "#{weather[:condition]}, #{weather[:current_temp]}C" : "Weather unavailable"
    germ_str = germ_plants.map { |p| "#{p.variety_name} day #{p.days_in_stage}" }.join(", ")

    payload = morning_brief_payload(
      task_count: tasks.count,
      weather_summary: weather_str,
      germination_alerts: germ_str.empty? ? nil : germ_str,
      dashboard_url: ENV.fetch("APP_URL", "http://garden.local:4567")
    )

    send!(**payload)
  end
end
