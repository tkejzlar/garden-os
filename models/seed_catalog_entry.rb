require_relative "../config/database"

class SeedCatalogEntry < Sequel::Model
  # Fuzzy search by variety name — case-insensitive, partial match
  def self.search(query)
    return [] if query.nil? || query.strip.empty?
    normalized = normalize(query)

    # Find all substring matches
    results = where(Sequel.like(:variety_name_normalized, "%#{normalized}%"))
      .limit(20)
      .all

    # Sort: exact matches first, then starts-with, then contains
    results.sort_by do |r|
      if r.variety_name_normalized == normalized
        [0, r.variety_name]
      elsif r.variety_name_normalized.start_with?(normalized)
        [1, r.variety_name]
      else
        [2, r.variety_name]
      end
    end.first(10)
  end

  # Normalize a string for matching: lowercase, strip accents, collapse whitespace
  def self.normalize(str)
    str.to_s.downcase
       .tr("áàâäãåčçďéèêëěíìîïňóòôöõřšťúùûüůýžñ",
           "aaaaaaccdeeeeeiiiinooooorstuuuuuyznc")
       .gsub(/[^a-z0-9\s]/, "")
       .gsub(/\s+/, " ")
       .strip
  end

  def notes_summary
    parts = [
      crop_subcategory,
      description&.slice(0, 200),
      days_to_maturity ? "#{days_to_maturity} days" : nil,
      germination_temp ? "Germ: #{germination_temp}" : nil,
      spacing ? "Spacing: #{spacing}" : nil,
      frost_tender ? "Frost tender" : (frost_tender == false ? "Frost hardy" : nil),
      sowing_info&.slice(0, 150)
    ].compact
    parts.join(". ")
  end
end
