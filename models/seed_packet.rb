require_relative "../config/database"

class SeedPacket < Sequel::Model
  def expired?
    sow_by_date && sow_by_date < Date.today
  end

  def expiring_soon?
    sow_by_date && !expired? && sow_by_date <= Date.today + 180
  end

  def out_of_stock?
    !quantity_remaining.nil? && quantity_remaining <= 0
  end
end
