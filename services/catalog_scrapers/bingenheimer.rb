module CatalogScrapers
  class Bingenheimer
    BASE = "https://www.bingenheimersaatgut.de"

    # Subcategory pages → crop_type mapping
    CATEGORIES = {
      "tomatoes"       => "tomato",
      "pepper"         => "pepper",
      "cucumbers"      => "cucumber",
      "beans"          => "bean",
      "peas"           => "pea",
      "cabbage"        => "brassica",
      "salad"          => "lettuce",
      "onions"         => "onion",
      "carrots"        => "root",
      "courgette"      => "squash",
      "squash"         => "squash",
      "aubergine"      => "other",
      "florence-fennel"=> "herb",
      "corn-salad"     => "lettuce",
      "chicory"        => "lettuce",
      "mustard-greens" => "brassica",
    }.freeze

    def self.scrape
      entries = []

      CATEGORIES.each do |subcategory, crop_type|
        sleep 1
        url = "#{BASE}/en/organic-seeds/vegetables/#{subcategory}.html"
        doc = CatalogScraper.fetch_page(url)
        next unless doc

        count_before = entries.length

        # Product links are like /en/organic-seeds/vegetables/tomatoes/bellarubin-g802
        doc.css("a[href*='/en/organic-seeds/vegetables/#{subcategory}/']").each do |link|
          href = link["href"]
          next if href.nil?
          next if href.include?("?") # skip filter/sort links
          next if href.end_with?("/#{subcategory}/") # skip self-link

          # Extract variety name from the <strong> tag inside the link, or from link text
          name = nil
          strong = link.css("strong").first
          if strong
            raw = strong.text.strip
            # Names come as "[Type VarietyName]" — strip brackets
            raw = raw.gsub(/\A\[/, "").gsub(/\]\z/, "").strip
            # Remove leading type prefix like "Standard Tomato ", "Cherry Tomato ", etc.
            # Keep the variety name (last word(s) after common type prefixes)
            name = strip_type_prefix(raw)
          else
            name = link.text.strip
          end

          next if name.nil? || name.empty? || name.length > 100

          full_url = href.start_with?("http") ? href : "#{BASE}#{href}"

          entries << {
            variety_name:     name,
            crop_type:        crop_type,
            crop_subcategory: nil,
            url:              full_url,
            article_number:   extract_sku(href),
            latin_name:       nil,
            description:      nil,
            germination_temp: nil,
            spacing:          nil,
            days_to_maturity: nil,
            sowing_info:      nil,
            frost_tender:     nil,
            direct_sow:       nil,
          }
        end

        puts "  #{subcategory}: #{entries.length - count_before} varieties"
      end

      # Deduplicate by URL
      entries.uniq { |e| e[:url] }
    end

    # Extract SKU from URL slug, e.g. ".../bellarubin-g802" → "G802"
    def self.extract_sku(href)
      if href =~ /-([gG]\d+)$/
        $1.upcase
      end
    end

    # Strip generic type prefixes like "Standard Tomato ", "Cherry Tomato ", etc.
    # so we get just the variety name (e.g. "Bellarubin")
    PREFIXES = %w[
      Standard Cherry Wild Cocktail Plum Beef Beefsteak Oxheart
      Round Oval Elongated
    ].freeze

    def self.strip_type_prefix(name)
      # Remove leading type words from compound names like "Standard Tomato Bellarubin"
      # Split on spaces, drop tokens that are generic descriptors, keep the rest
      tokens = name.split
      while tokens.length > 1 && PREFIXES.include?(tokens.first)
        tokens.shift
      end
      # Also remove the crop type word if present as second token (e.g. "Tomato", "Pepper")
      crop_words = %w[Tomato Pepper Cucumber Lettuce Bean Pea Squash Carrot Onion Brassica]
      while tokens.length > 1 && crop_words.include?(tokens.first)
        tokens.shift
      end
      tokens.join(" ")
    end
  end
end
