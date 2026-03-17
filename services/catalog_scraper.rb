require "nokogiri"
require "uri"
require_relative "../models/seed_catalog_entry"

class CatalogScraper
  SCRAPERS = %w[reinsaat bingenheimer sativa magic_garden loukykvet permaseminka].freeze

  def self.scrape_all!
    SCRAPERS.each { |s| scrape_supplier!(s) }
    prune!
  end

  def self.scrape_supplier!(name)
    require_relative "catalog_scrapers/#{name}"
    klass = Object.const_get("CatalogScrapers::#{name.split('_').map(&:capitalize).join}")
    puts "Scraping #{name}..."

    # Clear old entries for this supplier before re-scraping
    SeedCatalogEntry.where(supplier: name).delete

    entries = klass.scrape
    entries.each do |entry|
      SeedCatalogEntry.create(
        variety_name:            entry[:variety_name],
        variety_name_normalized: SeedCatalogEntry.normalize(entry[:variety_name]),
        crop_type:               entry[:crop_type],
        crop_subcategory:        entry[:crop_subcategory],
        supplier:                name,
        supplier_url:            entry[:url],
        article_number:          entry[:article_number],
        latin_name:              entry[:latin_name],
        description:             entry[:description],
        germination_temp:        entry[:germination_temp],
        spacing:                 entry[:spacing],
        days_to_maturity:        entry[:days_to_maturity],
        sowing_info:             entry[:sowing_info],
        frost_tender:            entry[:frost_tender],
        direct_sow:              entry[:direct_sow],
        scraped_at:              Time.now
      )
    end
    puts "  #{entries.length} varieties saved."
  end

  # Remove duplicates and junk entries
  def self.prune!
    before = SeedCatalogEntry.count

    # 1. Remove exact duplicates (same normalized name + supplier) — keep lowest ID
    DB["SELECT MIN(id) as keep_id, variety_name_normalized, supplier FROM seed_catalog_entries GROUP BY variety_name_normalized, supplier HAVING COUNT(*) > 1"].each do |g|
      SeedCatalogEntry.where(variety_name_normalized: g[:variety_name_normalized], supplier: g[:supplier])
        .exclude(id: g[:keep_id]).delete
    end

    # 2. Remove junk entries — Czech tags, navigation text, non-variety names
    junk = %w[mix\ barev lze\ susit novinka voni mix\ barevnovinka mixture trio\ of]
    junk.each { |j| SeedCatalogEntry.where(variety_name_normalized: j).delete }

    # 3. Remove very short names (likely scraping artifacts)
    SeedCatalogEntry.where { Sequel.char_length(:variety_name) < 3 }.delete

    after = SeedCatalogEntry.count
    puts "Pruned: #{before} → #{after} (removed #{before - after})"
  end

  # Shared HTTP fetch helper — uses curl for reliability (same pattern as WeatherService)
  def self.fetch_page(url, retries: 2)
    output = `curl -s --connect-timeout 10 --max-time 20 \
      -L \
      -H "User-Agent: GardenOS Seed Catalog Scraper/1.0" \
      -H "Accept: text/html,application/xhtml+xml" \
      "#{url}" 2>&1`

    if $?.exitstatus == 0 && !output.empty?
      return Nokogiri::HTML(output)
    end

    if retries > 0
      sleep 2
      return fetch_page(url, retries: retries - 1)
    end

    warn "  Failed to fetch #{url}"
    nil
  rescue => e
    warn "  Error fetching #{url}: #{e.message}"
    nil
  end
end
