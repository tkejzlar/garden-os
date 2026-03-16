require_relative "../test_helper"
require_relative "../../services/weather_service"

class TestWeatherService < GardenTest
  def test_parse_ha_weather_response
    mock_response = {
      "state" => "sunny",
      "attributes" => {
        "temperature" => 18.5,
        "forecast" => [
          { "datetime" => "2026-03-17", "temperature" => 15.0, "templow" => 2.0, "condition" => "cloudy" },
          { "datetime" => "2026-03-18", "temperature" => 12.0, "templow" => -1.0, "condition" => "snowy" },
          { "datetime" => "2026-03-19", "temperature" => 14.0, "templow" => 3.0, "condition" => "sunny" }
        ]
      }
    }

    weather = WeatherService.parse_forecast(mock_response)
    assert_equal 18.5, weather[:current_temp]
    assert_equal 3, weather[:forecast].length
    assert_equal true, weather[:frost_risk]
  end

  def test_frost_detection
    forecast = [
      { "templow" => 3.0 },
      { "templow" => 1.0 },
      { "templow" => -2.0 }
    ]
    assert WeatherService.frost_risk?(forecast)
  end

  def test_no_frost
    forecast = [
      { "templow" => 5.0 },
      { "templow" => 3.0 }
    ]
    refute WeatherService.frost_risk?(forecast)
  end
end
