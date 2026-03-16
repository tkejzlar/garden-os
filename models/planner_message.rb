require_relative "../config/database"

class PlannerMessage < Sequel::Model
  def draft?
    !draft_payload.nil? && !draft_payload.empty?
  end

  def draft_data
    draft? ? JSON.parse(draft_payload) : nil
  end
end
