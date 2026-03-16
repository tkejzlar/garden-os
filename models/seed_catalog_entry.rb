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

    desc = extract_description(doc)
    art = extract_article_number(doc)
    update(description: desc) if desc
    update(article_number: art) if art

    # Extract growing info from page text
    text = doc.css("body").text
    if (m = text.match(/(\d{1,2})\s*[-–]\s*(\d{1,2})\s*°C/))
      update(germination_temp: "#{m[1]}-#{m[2]}°C")
    end
    if (m = text.match(/(\d{2,3})\s*[x×]\s*(\d{2,3})\s*cm/))
      update(spacing: "#{m[1]}×#{m[2]}cm")
    end

    # Look for sowing/cultivation paragraphs
    sow_info = extract_sowing_info(doc)
    update(sowing_info: sow_info) if sow_info

    reload
  rescue => e
    warn "Enrich error for #{variety_name}: #{e.message}"
    self
  end

  private

  # Strip HTML tags from a string
  def strip_html(str)
    str.to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
  end

  # Catalog boilerplate to remove
  BOILERPLATE = /
    in\s+variety\s+testing|seeds?\s+for\s+trial\s+cultivation|
    thousand\s+grain\s+weight|portion\s+contents?|
    ready\s+to\s+ship|working\s+days?|add\s+to\s+cart|
    we\s+are\s+available|our\s+farm\s+shop
  /ix

  def clean_text(str)
    # Strip HTML, remove boilerplate sentences, collapse whitespace
    text = strip_html(str)
    sentences = text.split(/(?<=[.!?])\s+/)
    sentences.reject { |s| s.match?(BOILERPLATE) }.join(" ").strip
  end

  def extract_description(doc)
    # 1. JSON-LD Product description
    json_ld = doc.css('script[type="application/ld+json"]').map { |s| JSON.parse(s.text) rescue nil }.compact
    product = json_ld.find { |j| j["@type"] == "Product" }
    if product && product["description"]
      cleaned = clean_text(product["description"])
      return cleaned unless cleaned.empty? || cleaned.length < 20
    end

    # 2. Meta description
    meta = doc.at_css('meta[name="description"]')
    if meta && meta["content"]
      cleaned = clean_text(meta["content"])
      return cleaned unless cleaned.empty? || cleaned.length < 20
    end

    # 3. First meaningful paragraph with plant keywords
    plant_keywords = /fruit|taste|variety|plant|grow|seed|sow|harvest|ripen|resistant|height|flavor|colour|color|leaf|flower|pepper|tomato|cucumber/i
    skip_keywords = /cookie|©|phone|shop.*open|monday|shipping|delivery|cart|checkout|privacy|login|javascript/i
    doc.css("p, .product-description, [itemprop='description'], .description").each do |el|
      txt = el.text.strip
      next if txt.length < 30 || txt.length > 800
      next if txt.match?(skip_keywords)
      next unless txt.match?(plant_keywords)
      cleaned = clean_text(txt)
      return cleaned unless cleaned.empty?
    end

    nil
  end

  def extract_article_number(doc)
    json_ld = doc.css('script[type="application/ld+json"]').map { |s| JSON.parse(s.text) rescue nil }.compact
    product = json_ld.find { |j| j["@type"] == "Product" }
    product&.dig("model") || product&.dig("sku")
  end

  def extract_sowing_info(doc)
    # Look for paragraphs about sowing, cultivation, planting
    sow_keywords = /sow|pre-?cultiv|plant(?:ing|ed)|transplant|germination|cultivation|glasshouse|greenhouse|indoor|outdoor/i
    doc.css("p, li, dd, .product-info, .growing-info").each do |el|
      txt = el.text.strip
      next if txt.length < 20 || txt.length > 400
      if txt.match?(sow_keywords)
        cleaned = clean_text(txt)
        return cleaned unless cleaned.empty?
      end
    end
    nil
  end

  public

  def notes_summary
    parts = []
    parts << description if description && !description.empty?
    parts << "Germination: #{germination_temp}" if germination_temp
    parts << "Spacing: #{spacing}" if spacing
    # Only add sowing_info if it's different from the description
    if sowing_info && !sowing_info.empty? && sowing_info != description
      parts << sowing_info
    end
    parts << "Frost tender" if frost_tender == true
    parts << "Frost hardy" if frost_tender == false
    parts.join("\n")
  end
end
