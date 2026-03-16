require "ruby_llm"
require_relative "../../models/seed_packet"

class GetSeedInventoryTool < RubyLLM::Tool
  description "Get all seed packets the user has — variety names, crop types, sources, and growing notes"

  def execute
    packets = SeedPacket.order(:crop_type, :variety_name).all.map do |p|
      { variety_name: p.variety_name, crop_type: p.crop_type, source: p.source, notes: p.notes }
    end
    JSON.generate({ seed_packets: packets, total: packets.length })
  end
end
