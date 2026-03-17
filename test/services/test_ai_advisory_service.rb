require_relative "../test_helper"
require_relative "../../services/ai_advisory_service"

class TestAIAdvisoryService < GardenTest
  def test_builds_context_payload
    Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "germinating",
                 sow_date: Date.today - 5, garden_id: @garden.id)

    context = AIAdvisoryService.build_context
    assert context.key?(:plants)
    assert_equal 1, context[:plants].length
    assert_equal "Raf", context[:plants][0][:variety_name]
  end

  def test_parses_advisory_response
    mock_response = {
      "advisories" => [
        { "type" => "general", "summary" => "Good day for transplanting" },
        { "type" => "plant_specific", "plant" => "Raf", "summary" => "Check moisture" }
      ]
    }

    advisories = AIAdvisoryService.parse_response(mock_response)
    assert_equal 2, advisories.length
    assert_equal "general", advisories[0][:type]
  end

  def test_system_prompt_includes_prague
    prompt = AIAdvisoryService.system_prompt
    assert_includes prompt, "Prague"
  end

  def test_default_model
    assert_equal "claude-sonnet-4-6", AIAdvisoryService.model_id
  end

  def test_model_from_env
    ENV["GARDEN_AI_MODEL"] = "gpt-4o"
    assert_equal "gpt-4o", AIAdvisoryService.model_id
  ensure
    ENV.delete("GARDEN_AI_MODEL")
  end

  def test_build_context_includes_harvest_counts
    plant = Plant.create(variety_name: "Marmande", crop_type: "tomato", lifecycle_stage: "producing", garden_id: @garden.id)
    Harvest.create(plant_id: plant.id, date: Date.today, quantity: "large")
    Harvest.create(plant_id: plant.id, date: Date.today, quantity: "large")
    Harvest.create(plant_id: plant.id, date: Date.today, quantity: "small")

    context = AIAdvisoryService.build_context
    plant_ctx = context[:plants].find { |p| p[:variety_name] == "Marmande" }

    refute_nil plant_ctx
    assert_equal 3,              plant_ctx[:total_harvests]
    assert_equal 2,              plant_ctx[:harvest_counts]["large"]
    assert_equal 1,              plant_ctx[:harvest_counts]["small"]
  end
end
