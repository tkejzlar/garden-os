require "ruby_llm"
require_relative "../weather_service"

class GetWeatherTool < RubyLLM::Tool
  description "Get current weather conditions and 3-day forecast for the garden location"

  def execute
    weather = WeatherService.fetch_current
    if weather
      JSON.generate(weather)
    else
      JSON.generate({ error: "Weather data unavailable" })
    end
  end
end
