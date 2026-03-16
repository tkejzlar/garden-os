require_relative "../config/database"

class SuccessionPlan < Sequel::Model
  def varieties_list
    varieties ? JSON.parse(varieties) : []
  end

  def target_beds_list
    target_beds ? JSON.parse(target_beds) : []
  end

  def next_sowing_date(completed_sowings_count)
    return nil unless season_start
    season_start + (interval_days * completed_sowings_count)
  end
end
