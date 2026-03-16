require "json"
require "httpx"

class WeatherService
  def self.ha_url     = ENV.fetch("HA_URL", "http://homeassistant.local:8123")
  def self.ha_token   = ENV.fetch("HA_TOKEN", "")
  def self.weather_entity = ENV.fetch("HA_WEATHER_ENTITY", "weather.home")

  def self.fetch_current
    return nil if ha_token.empty?

    response = HTTPX.with(
      headers: {
        "Authorization" => "Bearer #{ha_token}",
        "Content-Type" => "application/json"
      }
    ).get("#{ha_url}/api/states/#{weather_entity}")

    return nil unless response.status == 200
    parse_forecast(JSON.parse(response.body.to_s))
  rescue => e
    warn "WeatherService error: #{e.message}"
    nil
  end

  def self.parse_forecast(data)
    attrs = data["attributes"] || {}
    forecast = attrs["forecast"] || []

    {
      current_temp: attrs["temperature"],
      condition: data["state"],
      forecast: forecast.first(3).map do |day|
        {
          date: day["datetime"],
          high: day["temperature"],
          low: day["templow"],
          condition: day["condition"]
        }
      end,
      frost_risk: frost_risk?(forecast)
    }
  end

  def self.frost_risk?(forecast)
    forecast.any? { |day| (day["templow"] || day[:low]).to_f <= 0 }
  end
end
