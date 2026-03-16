module CatalogScrapers
  class MagicGarden
    BASE     = "https://www.magicgardenseeds.com"
    CATEGORY = "Vegetable-Seeds"

    # Keyword patterns in product names → crop_type
    CROP_KEYWORDS = [
      [/\btomato\b|\btomatoes\b|\bsolanum lycopersicum\b/i, "tomato"],
      [/\bpepper\b|\bchilli\b|\bchili\b|\bcapsicum\b/i, "pepper"],
      [/\bcucumber\b|\bgherkin\b|\bcucumis\b/i, "cucumber"],
      [/\blettuce\b|\bsalad\b|\blactuca\b/i, "lettuce"],
      [/\bradish\b|\brephanus\b/i, "radish"],
      [/\bbean\b|\bphaseolus\b|\bvicia faba\b/i, "bean"],
      [/\bpea\b|\bpisum\b/i, "pea"],
      [/\bsquash\b|\bpumpkin\b|\bzucchini\b|\bcourgette\b|\bcucurbita\b/i, "squash"],
      [/\bbrassica\b|\bbrocco\b|\bcabbage\b|\bkale\b|\bkohlrabi\b|\bcauliflower\b/i, "brassica"],
      [/\bonion\b|\bleek\b|\ballium\b|\bgarlic\b/i, "onion"],
      [/\bcarrot\b|\bbeetroot\b|\bparsnip\b|\bradicchio\b|\bsalsify\b|\bturnip\b/i, "root"],
      [/\bbasil\b|\bparsley\b|\bdill\b|\bcoriander\b|\bfennel\b|\bcelery\b|\bherb\b/i, "herb"],
    ].freeze

    def self.scrape
      entries = []

      # Discover total pages by fetching page 1 and looking for pagination
      first_doc = CatalogScraper.fetch_page("#{BASE}/#{CATEGORY}")
      return entries unless first_doc

      total_pages = discover_total_pages(first_doc)
      puts "  Magic Garden: #{total_pages} pages to scrape"

      (1..total_pages).each do |page|
        sleep 1
        url = page == 1 ? "#{BASE}/#{CATEGORY}" : "#{BASE}/#{CATEGORY}_s#{page}"
        doc = page == 1 ? first_doc : CatalogScraper.fetch_page(url)
        next unless doc

        count_before = entries.length

        # Product titles are in <div class="productbox-title" itemprop="name">
        doc.css("div.productbox-title[itemprop='name'], div[itemprop='name']").each do |title_div|
          link = title_div.css("a").first
          next unless link

          href = link["href"]
          name = link.text.strip
          next if name.empty? || name.length > 200
          next unless href

          # Normalize URL
          full_url = href.start_with?("http") ? href : "#{BASE}#{href}"

          # Determine crop type from product name
          crop_type = classify_crop(name)

          # Extract clean variety name (strip botanical names in parentheses and "seeds" suffix)
          variety_name = clean_variety_name(name)
          next if variety_name.empty?

          entries << {
            variety_name:     variety_name,
            crop_type:        crop_type,
            crop_subcategory: nil,
            url:              full_url,
            article_number:   nil,
            latin_name:       extract_latin_name(name),
            description:      nil,
            germination_temp: nil,
            spacing:          nil,
            days_to_maturity: nil,
            sowing_info:      nil,
            frost_tender:     nil,
            direct_sow:       nil,
          }
        end

        puts "  Page #{page}: #{entries.length - count_before} varieties (#{entries.length} total)"
      end

      entries.uniq { |e| e[:url] }
    end

    def self.discover_total_pages(doc)
      # Try to find total item count like "Items 1 - 20 of 608"
      text = doc.text
      if text =~ /Items\s+\d+\s*-\s*(\d+)\s+of\s+(\d+)/i
        per_page = $1.to_i
        total    = $2.to_i
        return [(total.to_f / per_page).ceil, 1].max if per_page > 0
      end

      # Fallback: look for pagination links like /Vegetable-Seeds_s9
      max_page = 1
      doc.css("a[href*='#{CATEGORY}_s']").each do |link|
        href = link["href"]
        if href =~ /_s(\d+)/
          n = $1.to_i
          max_page = n if n > max_page
        end
      end
      max_page
    end

    def self.classify_crop(name)
      CROP_KEYWORDS.each do |pattern, crop_type|
        return crop_type if name =~ pattern
      end
      "other"
    end

    # Remove botanical name in parentheses, trailing "seeds", "organic seeds" etc.
    # e.g. "Plum Cherry Tomato 'Principe Borghese' (Solanum lycopersicum) seeds"
    #   → "Plum Cherry Tomato 'Principe Borghese'"
    def self.clean_variety_name(name)
      # Remove trailing "(Latin name) seeds" or just "seeds"/"organic seeds"
      cleaned = name.gsub(/\s*\([^)]+\)\s*(organic\s+)?seeds?\s*\z/i, "")
                    .gsub(/\s*(organic\s+)?seeds?\s*\z/i, "")
                    .strip

      # Extract variety in single quotes if present: "Plum Cherry Tomato 'Principe Borghese'"
      # → "Principe Borghese"
      if cleaned =~ /[''']([^''']+)[''']/
        return $1.strip
      end

      cleaned
    end

    # Extract Latin/botanical name from parentheses: "(Solanum lycopersicum)" → "Solanum lycopersicum"
    def self.extract_latin_name(name)
      if name =~ /\(([A-Z][a-z]+ [a-z].*?)\)/
        $1.strip
      end
    end
  end
end
