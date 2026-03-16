require "json"

class WeatherService
  def self.ha_url         = ENV.fetch("HA_URL", "http://homeassistant.local:8123")
  def self.ha_token       = ENV.fetch("HA_TOKEN", "")
  def self.weather_entity = ENV.fetch("HA_WEATHER_ENTITY", "weather.forecast_home")

  def self.fetch_current
    return nil if ha_token.empty?

    # 1. Current conditions from entity state
    state_data = ha_get("/api/states/#{weather_entity}")
    return nil unless state_data

    # 2. Forecast via service call (HA 2024+ moved forecasts here)
    forecast_resp = ha_post(
      "/api/services/weather/get_forecasts?return_response",
      { type: "daily", entity_id: weather_entity }
    )
    forecast = forecast_resp&.dig("service_response", weather_entity, "forecast") || []

    attrs = state_data["attributes"] || {}
    {
      current_temp: attrs["temperature"],
      condition: state_data["state"],
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
  rescue => e
    warn "WeatherService error: #{e.message}"
    nil
  end

  def self.frost_risk?(forecast)
    forecast.any? { |day| (day["templow"] || day[:low]).to_f <= 0 }
  end

  def self.parse_forecast(data)
    # Kept for backward compatibility with tests
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

  private

  # Use curl for HA requests — Net::HTTP has connectivity issues with
  # local network on macOS/Ruby 3.2 where curl works reliably.
  def self.ha_get(path)
    output = `curl -s --connect-timeout 5 --max-time 10 \
      -H "Authorization: Bearer #{ha_token}" \
      -H "Content-Type: application/json" \
      "#{ha_url}#{path}" 2>&1`
    return nil if output.empty? || $?.exitstatus != 0
    JSON.parse(output)
  rescue => e
    warn "WeatherService HA GET error: #{e.message}"
    nil
  end

  def self.ha_post(path, payload)
    json_payload = JSON.generate(payload)
    output = `curl -s --connect-timeout 5 --max-time 10 \
      -X POST \
      -H "Authorization: Bearer #{ha_token}" \
      -H "Content-Type: application/json" \
      -d '#{json_payload}' \
      "#{ha_url}#{path}" 2>&1`
    return nil if output.empty? || $?.exitstatus != 0
    JSON.parse(output)
  rescue => e
    warn "WeatherService HA POST error: #{e.message}"
    nil
  end
end
