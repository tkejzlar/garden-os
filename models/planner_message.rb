require "json"
require_relative "../config/database"

class PlannerMessage < Sequel::Model
  many_to_one :garden

  def draft?
    !draft_payload.nil? && !draft_payload.empty?
  end

  def draft_data
    draft? ? JSON.parse(draft_payload) : nil
  end
end
