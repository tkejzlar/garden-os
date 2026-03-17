require_relative "../config/database"

class Advisory < Sequel::Model
  many_to_one :garden
  many_to_one :plant

  def content_hash
    JSON.parse(content)
  end
end
