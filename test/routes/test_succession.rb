require_relative "../test_helper"
require_relative "../../app"

class TestSuccession < GardenTest
  def test_succession_index
    get "/succession"
    assert_equal 200, last_response.status
  end

  def test_succession_page_includes_alpine_component
    SuccessionPlan.create(crop: "Lettuce", varieties: '["Tre Colori"]',
                          interval_days: 18, total_planned_sowings: 8)
    get "/succession"
    assert_includes last_response.body, "x-data=\"gantt()\""
  end

  def test_succession_api_still_works
    SuccessionPlan.create(crop: "Lettuce", varieties: '["Tre Colori"]',
                          interval_days: 18, total_planned_sowings: 8,
                          season_start: Date.today, season_end: Date.today + 90,
                          target_beds: '["BB1"]')
    get "/api/succession"
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal "Lettuce", body.first["crop"]
  end
end
