# test/services/test_variety_lookup_service.rb
require_relative "../test_helper"
require_relative "../../services/variety_lookup_service"

class TestVarietyLookupService < GardenTest
  def test_parses_valid_response
    mock_json = {
      "crop_type" => "tomato",
      "variety_notes" => "Marmande-type beefsteak from Spain, 75-80 days to maturity",
      "days_to_maturity" => "75-80",
      "frost_tender" => true,
      "sow_indoor_weeks_before_last_frost" => 8,
      "direct_sow" => false
    }
    result = VarietyLookupService.parse_response(mock_json)
    assert_equal "tomato", result[:crop_type]
    assert_includes result[:notes], "Marmande"
    assert result[:frost_tender]
  end

  def test_system_prompt_mentions_json
    prompt = VarietyLookupService.system_prompt
    assert_includes prompt, "JSON"
  end

  def test_handles_empty_response
    result = VarietyLookupService.parse_response({})
    assert_nil result[:crop_type]
  end
end
