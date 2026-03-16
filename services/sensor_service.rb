require "json"

class SensorService
  def self.ha_url    = ENV.fetch("HA_URL", "http://homeassistant.local:8123")
  def self.ha_token  = ENV.fetch("HA_TOKEN", "")

  # Returns array of zone hashes: [{name:, entity_id:, state:, next_run:}]
  # state is one of: "idle", "running", "offline"
  # next_run is the HA attribute "next_cycle" (string) or nil
  def self.fetch_zones
    zone_ids = ENV.fetch("HA_HYDRAWISE_ZONES", "").split(",").map(&:strip).reject(&:empty?)
    return [] if zone_ids.empty? || ha_token.empty?

    zone_ids.map do |entity_id|
      data = ha_get("/api/states/#{entity_id}")
      next nil unless data

      attrs = data["attributes"] || {}
      raw_state = data["state"].to_s.downcase

      state = case raw_state
              when "on"  then "running"
              when "off" then "idle"
              else            "offline"
              end

      {
        name:      attrs["friendly_name"] || entity_id,
        entity_id: entity_id,
        state:     state,
        next_run:  attrs["next_cycle"]
      }
    end.compact
  rescue => e
    warn "SensorService#fetch_zones error: #{e.message}"
    []
  end

  # Returns {temp:, entity_id:, warning:} or nil if not configured / unreachable
  # warning is true when temp is outside the 25–32°C heat mat sweet spot
  def self.fetch_indoor_temp
    entity_id = ENV.fetch("HA_INDOOR_TEMP_ENTITY", "")
    return nil if entity_id.empty? || ha_token.empty?

    data = ha_get("/api/states/#{entity_id}")
    return nil unless data

    temp = data["state"].to_f
    {
      temp:      temp,
      entity_id: entity_id,
      warning:   temp < 25.0 || temp > 32.0
    }
  rescue => e
    warn "SensorService#fetch_indoor_temp error: #{e.message}"
    nil
  end

  # Returns true when the HA binary rain sensor is "on", false otherwise.
  # Returns false (not nil) when the sensor is unconfigured so callers can
  # use the result directly in boolean logic without nil-guarding.
  def self.rain_detected?
    entity_id = ENV.fetch("HA_RAIN_SENSOR", "")
    return false if entity_id.empty? || ha_token.empty?

    data = ha_get("/api/states/#{entity_id}")
    return false unless data

    data["state"].to_s.downcase == "on"
  rescue => e
    warn "SensorService#rain_detected? error: #{e.message}"
    false
  end

  # Convenience: true when any Hydrawise zone is currently running
  def self.irrigation_active?
    fetch_zones.any? { |z| z[:state] == "running" }
  end

  private

  def self.ha_get(path)
    output = `curl -s --connect-timeout 5 --max-time 10 \
      -H "Authorization: Bearer #{ha_token}" \
      -H "Content-Type: application/json" \
      "#{ha_url}#{path}" 2>&1`
    return nil if output.empty? || $?.exitstatus != 0
    JSON.parse(output)
  rescue => e
    warn "SensorService HA GET error: #{e.message}"
    nil
  end
end
