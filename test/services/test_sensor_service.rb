require_relative "../test_helper"
require_relative "../../services/sensor_service"

# Minimal stub helper: temporarily replaces a class method with a value/proc
module ClassStub
  def stub(method_name, val_or_callable, &block)
    original = method(method_name)
    define_singleton_method(method_name) do |*a|
      val_or_callable.respond_to?(:call) ? val_or_callable.call(*a) : val_or_callable
    end
    block.call
  ensure
    define_singleton_method(method_name, original)
  end
end

SensorService.extend(ClassStub)

class TestSensorService < GardenTest
  # ---------------------------------------------------------------------------
  # fetch_zones
  # ---------------------------------------------------------------------------

  def test_fetch_zones_returns_empty_when_env_not_set
    ENV.delete("HA_HYDRAWISE_ZONES")
    assert_equal [], SensorService.fetch_zones
  end

  def test_fetch_zones_parses_running_zone
    ENV["HA_HYDRAWISE_ZONES"] = "switch.hydrawise_zone_1"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = {
      "state" => "on",
      "attributes" => {
        "friendly_name" => "Zone 1 — Raised Beds",
        "next_cycle" => "2026-03-17T06:00:00"
      }
    }

    SensorService.stub(:ha_get, mock_response) do
      zones = SensorService.fetch_zones
      assert_equal 1, zones.length
      assert_equal "running", zones.first[:state]
      assert_equal "Zone 1 — Raised Beds", zones.first[:name]
      assert_equal "2026-03-17T06:00:00", zones.first[:next_run]
    end
  ensure
    ENV.delete("HA_HYDRAWISE_ZONES")
    ENV.delete("HA_TOKEN")
  end

  def test_fetch_zones_parses_idle_zone
    ENV["HA_HYDRAWISE_ZONES"] = "switch.hydrawise_zone_2"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = {
      "state" => "off",
      "attributes" => { "friendly_name" => "Zone 2" }
    }

    SensorService.stub(:ha_get, mock_response) do
      zones = SensorService.fetch_zones
      assert_equal "idle", zones.first[:state]
    end
  ensure
    ENV.delete("HA_HYDRAWISE_ZONES")
    ENV.delete("HA_TOKEN")
  end

  def test_fetch_zones_returns_offline_for_unavailable_entity
    ENV["HA_HYDRAWISE_ZONES"] = "switch.hydrawise_zone_1"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = {
      "state" => "unavailable",
      "attributes" => {}
    }

    SensorService.stub(:ha_get, mock_response) do
      zones = SensorService.fetch_zones
      assert_equal "offline", zones.first[:state]
    end
  ensure
    ENV.delete("HA_HYDRAWISE_ZONES")
    ENV.delete("HA_TOKEN")
  end

  # ---------------------------------------------------------------------------
  # fetch_indoor_temp
  # ---------------------------------------------------------------------------

  def test_fetch_indoor_temp_returns_nil_when_not_configured
    ENV.delete("HA_INDOOR_TEMP_ENTITY")
    assert_nil SensorService.fetch_indoor_temp
  end

  def test_fetch_indoor_temp_no_warning_in_range
    ENV["HA_INDOOR_TEMP_ENTITY"] = "sensor.indoor_temperature"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = { "state" => "28.5", "attributes" => {} }

    SensorService.stub(:ha_get, mock_response) do
      result = SensorService.fetch_indoor_temp
      assert_equal 28.5, result[:temp]
      assert_equal false, result[:warning]
    end
  ensure
    ENV.delete("HA_INDOOR_TEMP_ENTITY")
    ENV.delete("HA_TOKEN")
  end

  def test_fetch_indoor_temp_warning_when_too_cold
    ENV["HA_INDOOR_TEMP_ENTITY"] = "sensor.indoor_temperature"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = { "state" => "22.0", "attributes" => {} }

    SensorService.stub(:ha_get, mock_response) do
      result = SensorService.fetch_indoor_temp
      assert_equal true, result[:warning]
    end
  ensure
    ENV.delete("HA_INDOOR_TEMP_ENTITY")
    ENV.delete("HA_TOKEN")
  end

  def test_fetch_indoor_temp_warning_when_too_hot
    ENV["HA_INDOOR_TEMP_ENTITY"] = "sensor.indoor_temperature"
    ENV["HA_TOKEN"] = "fake-token"

    mock_response = { "state" => "35.0", "attributes" => {} }

    SensorService.stub(:ha_get, mock_response) do
      result = SensorService.fetch_indoor_temp
      assert_equal true, result[:warning]
    end
  ensure
    ENV.delete("HA_INDOOR_TEMP_ENTITY")
    ENV.delete("HA_TOKEN")
  end

  # ---------------------------------------------------------------------------
  # rain_detected?
  # ---------------------------------------------------------------------------

  def test_rain_detected_false_when_not_configured
    ENV.delete("HA_RAIN_SENSOR")
    refute SensorService.rain_detected?
  end

  def test_rain_detected_true_when_sensor_on
    ENV["HA_RAIN_SENSOR"] = "binary_sensor.hydrawise_rain_sensor"
    ENV["HA_TOKEN"] = "fake-token"

    SensorService.stub(:ha_get, { "state" => "on", "attributes" => {} }) do
      assert SensorService.rain_detected?
    end
  ensure
    ENV.delete("HA_RAIN_SENSOR")
    ENV.delete("HA_TOKEN")
  end

  def test_rain_detected_false_when_sensor_off
    ENV["HA_RAIN_SENSOR"] = "binary_sensor.hydrawise_rain_sensor"
    ENV["HA_TOKEN"] = "fake-token"

    SensorService.stub(:ha_get, { "state" => "off", "attributes" => {} }) do
      refute SensorService.rain_detected?
    end
  ensure
    ENV.delete("HA_RAIN_SENSOR")
    ENV.delete("HA_TOKEN")
  end

  def test_rain_detected_false_when_ha_unreachable
    ENV["HA_RAIN_SENSOR"] = "binary_sensor.hydrawise_rain_sensor"
    ENV["HA_TOKEN"] = "fake-token"

    SensorService.stub(:ha_get, nil) do
      refute SensorService.rain_detected?
    end
  ensure
    ENV.delete("HA_RAIN_SENSOR")
    ENV.delete("HA_TOKEN")
  end

  # ---------------------------------------------------------------------------
  # irrigation_active?
  # ---------------------------------------------------------------------------

  def test_irrigation_active_true_when_zone_running
    SensorService.stub(:fetch_zones, [{ state: "running", name: "Zone 1", entity_id: "x", next_run: nil }]) do
      assert SensorService.irrigation_active?
    end
  end

  def test_irrigation_active_false_when_all_idle
    SensorService.stub(:fetch_zones, [{ state: "idle", name: "Zone 1", entity_id: "x", next_run: nil }]) do
      refute SensorService.irrigation_active?
    end
  end
end
