module CatalogScrapers
  class MagicGarden
    BASE = "https://www.magicgardenseeds.com"

    # All seed sections — themed + standard
    SECTIONS = %w[Vegetable-Seeds Herb-Seeds Flower-Seeds Beautiful Magical Aromatic Exotic Beneficial].freeze

    # Fine-grained crop type keywords
    CROP_KEYWORDS = [
      [/\btomato\b|\btomatoes\b|\bsolanum lycopersicum\b/i, "tomato"],
      [/\bpepper\b|\bchilli\b|\bchili\b|\bcapsicum\b|\bhabanero\b|\bjalapeno\b/i, "pepper"],
      [/\bcucumber\b|\bgherkin\b|\bcucumis\b/i, "cucumber"],
      [/\blettuce\b|\blactuca\b/i, "lettuce"],
      [/\bradish\b|\braphanus\b/i, "radish"],
      [/\bbean\b|\bphaseolus\b|\bvicia faba\b|\bborlotto\b/i, "bean"],
      [/\bpea\b|\bpisum\b/i, "pea"],
      [/\bsquash\b|\bpumpkin\b|\bzucchini\b|\bcourgette\b|\bcucurbita\b/i, "squash"],
      [/\bbrassica\b|\bbrocco\b|\bcabbage\b|\bkale\b|\bkohlrabi\b|\bcauliflower\b/i, "brassica"],
      [/\bleek\b|\bporee\b/i, "leek"],
      [/\bonion\b|\ballium\b|\bgarlic\b|\bshallot\b/i, "onion"],
      [/\bcarrot\b|\bdaucus\b/i, "carrot"],
      [/\bbeetroot\b|\bbeet\b|\bbeta vulgaris\b/i, "beetroot"],
      [/\bparsnip\b/i, "parsnip"],
      [/\bturnip\b|\bswede\b/i, "turnip"],
      [/\bcelery\b|\bceleriac\b/i, "celery"],
      [/\baubergine\b|\beggplant\b/i, "aubergine"],
      [/\bmelon\b/i, "melon"],
      [/\bchard\b|\bmangold\b/i, "chard"],
      [/\bspinach\b/i, "spinach"],
      [/\bcorn\b|\bmaize\b|\bzea mays\b/i, "sweetcorn"],
      [/\bmorning glory\b|\bipom[oe]ea\b|\bnasturtium\b|\bsunflower\b|\bcosmos\b|\bzinnia\b|\bmarigold\b|\bsweet pea\b|\baster\b/i, "flower"],
      [/\bbasil\b|\bparsley\b|\bdill\b|\bcoriander\b|\bfennel\b|\bherb\b|\bthyme\b|\bsage\b|\bmint\b|\boregano\b|\blavender\b|\brosemary\b|\bchive\b/i, "herb"],
    ].freeze

    def self.scrape
      entries = []

      SECTIONS.each do |section|
        first_doc = CatalogScraper.fetch_page("#{BASE}/#{section}")
        next unless first_doc

        total_pages = discover_total_pages(first_doc, section)
        puts "  #{section}: #{total_pages} pages"

        # Default crop type based on section
        section_default = case section
                          when "Herb-Seeds" then "herb"
                          when "Flower-Seeds" then "flower"
                          else nil
                          end

        (1..total_pages).each do |page|
          sleep 1
          url = page == 1 ? "#{BASE}/#{section}" : "#{BASE}/#{section}_s#{page}"
          doc = page == 1 ? first_doc : CatalogScraper.fetch_page(url)
          next unless doc

          count_before = entries.length

          doc.css("div.productbox-title[itemprop='name'], div[itemprop='name']").each do |title_div|
          link = title_div.css("a").first
          next unless link

          href = link["href"]
          name = link.text.strip
          next if name.empty? || name.length > 200
          next unless href

          # Normalize URL
          full_url = href.start_with?("http") ? href : "#{BASE}#{href}"

          # Determine crop type from product name, fall back to section default
          crop_type = classify_crop(name) || section_default || "other"

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

        puts "  #{section} p#{page}: #{entries.length - count_before} varieties (#{entries.length} total)"
        end
      end

      entries.uniq { |e| e[:url] }
    end

    def self.discover_total_pages(doc, section = "Vegetable-Seeds")
      # Try to find total item count like "Items 1 - 20 of 608"
      text = doc.text
      if text =~ /Items\s+\d+\s*-\s*(\d+)\s+of\s+(\d+)/i
        per_page = $1.to_i
        total    = $2.to_i
        return [(total.to_f / per_page).ceil, 1].max if per_page > 0
      end

      # Fallback: look for pagination links like /Vegetable-Seeds_s9
      max_page = 1
      doc.css("a[href*='#{section}_s']").each do |link|
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
      nil  # no match — caller uses section default
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
