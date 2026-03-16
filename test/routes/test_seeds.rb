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
    post "/seeds", variety_name: "Sungold", crop_type: "tomato", source: "Reinsaat"
    assert_equal 302, last_response.status
    assert_equal 1, SeedPacket.count
    packet = SeedPacket.first
    assert_equal "Sungold", packet.variety_name
    assert_equal "tomato", packet.crop_type
    assert_equal "Reinsaat", packet.source
  end

  def test_create_seed_packet_with_notes
    post "/seeds", variety_name: "Raf", crop_type: "tomato",
                   notes: "Flesh tomato, 75-80 days"
    assert_equal 302, last_response.status
    assert_equal "Flesh tomato, 75-80 days", SeedPacket.first.notes
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
  end

  def test_new_form_renders
    get "/seeds/new"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Add Seed"
  end
end
