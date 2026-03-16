require_relative "../test_helper"
require_relative "../../app"

class TestSeeds < GardenTest
  def test_seeds_index_empty
    get "/seeds"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "No seed packets tracked yet"
  end

  def test_seeds_index_lists_packets
    SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                      created_at: Time.now, updated_at: Time.now)
    get "/seeds"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sungold"
  end

  def test_seeds_show
    packet = SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                               created_at: Time.now, updated_at: Time.now)
    get "/seeds/#{packet.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sungold"
  end

  def test_seeds_show_404
    get "/seeds/999999"
    assert_equal 404, last_response.status
  end

  def test_create_seed_packet
    post "/seeds", variety_name: "Sungold", crop_type: "tomato",
                   source: "Loukykvět", quantity_remaining: "10"
    assert_equal 302, last_response.status
    assert_equal 1, SeedPacket.count
    packet = SeedPacket.first
    assert_equal "Sungold", packet.variety_name
    assert_equal "tomato",  packet.crop_type
    assert_equal 10,        packet.quantity_remaining
  end

  def test_create_seed_packet_with_sow_by_date
    post "/seeds", variety_name: "Basil", crop_type: "herb",
                   sow_by_date: "2027-01-01"
    assert_equal 302, last_response.status
    assert_equal Date.new(2027, 1, 1), SeedPacket.first.sow_by_date
  end

  def test_update_seed_packet
    packet = SeedPacket.create(variety_name: "Old Name", crop_type: "tomato",
                               created_at: Time.now, updated_at: Time.now)
    patch "/seeds/#{packet.id}", variety_name: "New Name", crop_type: "tomato"
    assert_equal 302, last_response.status
    assert_equal "New Name", packet.reload.variety_name
  end

  def test_delete_seed_packet
    packet = SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                               created_at: Time.now, updated_at: Time.now)
    delete "/seeds/#{packet.id}"
    assert_equal 302, last_response.status
    assert_equal 0, SeedPacket.count
  end

  def test_api_seeds
    SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                      created_at: Time.now, updated_at: Time.now)
    get "/api/seeds"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 1, data.length
    assert_equal "Sungold", data.first["variety_name"]
  end

  def test_seeds_grouped_by_crop_type
    SeedPacket.create(variety_name: "Sungold", crop_type: "tomato",
                      created_at: Time.now, updated_at: Time.now)
    SeedPacket.create(variety_name: "Genovese", crop_type: "herb",
                      created_at: Time.now, updated_at: Time.now)
    get "/seeds"
    body = last_response.body
    assert_includes body, "tomato"
    assert_includes body, "herb"
    tomato_pos = body.index("tomato")
    herb_pos   = body.index("herb")
    assert herb_pos > tomato_pos, "herb section should appear after tomato (alphabetical)"
  end

  def test_expired_model_helper
    packet = SeedPacket.new(sow_by_date: Date.today - 1)
    assert packet.expired?
    refute packet.expiring_soon?
  end

  def test_expiring_soon_model_helper
    packet = SeedPacket.new(sow_by_date: Date.today + 90)
    refute packet.expired?
    assert packet.expiring_soon?
  end

  def test_out_of_stock_model_helper
    assert SeedPacket.new(quantity_remaining: 0).out_of_stock?
    assert SeedPacket.new(quantity_remaining: -1).out_of_stock?
    refute SeedPacket.new(quantity_remaining: 1).out_of_stock?
    refute SeedPacket.new(quantity_remaining: nil).out_of_stock?
  end
end
