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

  # Fetch and cache product detail from supplier page
  def enrich!
    return self if description && !description.empty?  # already enriched
    return self unless supplier_url && !supplier_url.empty?

    require_relative "../services/catalog_scraper"
    doc = CatalogScraper.fetch_page(supplier_url)
    return self unless doc

    # Extract text content — works for most supplier pages
    # Try JSON-LD first (Reinsaat uses this)
    json_ld = doc.css('script[type="application/ld+json"]').map { |s| JSON.parse(s.text) rescue nil }.compact
    product = json_ld.find { |j| j["@type"] == "Product" }

    if product
      update(
        description: product["description"]&.strip,
        article_number: product["model"] || product["sku"]
      )
    end

    # Fallback: meta description
    if description.nil? || description.empty?
      meta = doc.at_css('meta[name="description"]')
      update(description: meta["content"].strip) if meta && meta["content"] && !meta["content"].strip.empty?
    end

    # Fallback: find a paragraph that looks like a product description
    # (contains plant-related keywords, not store hours or legal text)
    if description.nil? || description.empty?
      plant_keywords = /fruit|taste|variety|plant|grow|seed|sow|harvest|ripen|resistant|height|flavor|colour|color|leaf|flower/i
      skip_keywords = /cookie|©|phone|shop.*open|monday|shipping|delivery|cart|checkout|privacy|login/i
      doc.css("p, .product-description, [itemprop='description']").each do |el|
        txt = el.text.strip
        if txt.length > 40 && txt.length < 600 && txt.match?(plant_keywords) && !txt.match?(skip_keywords)
          update(description: txt)
          break
        end
      end
    end

    # Try to extract growing info from page text
    text = doc.css("body").text
    if (m = text.match(/(\d{1,2})\s*[-–]\s*(\d{1,2})\s*°C/))
      update(germination_temp: "#{m[1]}-#{m[2]}°C")
    end
    if (m = text.match(/(\d{2,3})\s*[x×]\s*(\d{2,3})\s*cm/))
      update(spacing: "#{m[1]}×#{m[2]}cm")
    end
    if (m = text.match(/(\d+[.,]?\d*)\s*[-–]\s*(\d+[.,]?\d*)\s*cm.*(?:depth|deep|sowing)/i))
      update(sowing_info: "Sowing depth: #{m[0]}")
    end

    reload
  rescue => e
    warn "Enrich error for #{variety_name}: #{e.message}"
    self
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
