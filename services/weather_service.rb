require "json"
require "httpx"

class WeatherService
  HA_URL = ENV.fetch("HA_URL", "http://homeassistant.local:8123")
  HA_TOKEN = ENV.fetch("HA_TOKEN", "")
  WEATHER_ENTITY = ENV.fetch("HA_WEATHER_ENTITY", "weather.home")

  def self.fetch_current
    return nil if HA_TOKEN.empty?

    response = HTTPX.with(
      headers: {
        "Authorization" => "Bearer #{HA_TOKEN}",
        "Content-Type" => "application/json"
      }
    ).get("#{HA_URL}/api/states/#{WEATHER_ENTITY}")

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
