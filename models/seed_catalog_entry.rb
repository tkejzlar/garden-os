require_relative "../config/database"

class SeedCatalogEntry < Sequel::Model
  # Fuzzy search by variety name — case-insensitive, partial match
  def self.search(query)
    return [] if query.nil? || query.strip.empty?
    normalized = normalize(query)
    where(Sequel.like(:variety_name_normalized, "%#{normalized}%"))
      .order(:variety_name)
      .limit(10)
      .all
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
