module CatalogScrapers
  class Bingenheimer
    BASE = "https://www.bingenheimersaatgut.de"

    # Complete subcategory list with fine-grained crop types
    VEGETABLE_CATEGORIES = {
      "tomatoes"            => "tomato",
      "pepper"              => "pepper",
      "cucumbers"           => "cucumber",
      "beans"               => "bean",
      "peas"                => "pea",
      "cabbage"             => "brassica",
      "salad"               => "lettuce",
      "corn-salad"          => "lettuce",
      "chicory"             => "lettuce",
      "chicory-sugar-loafs" => "lettuce",
      "rucola"              => "lettuce",
      "onions"              => "onion",
      "bunching-onion"      => "onion",
      "leeks"               => "leek",
      "carrots"             => "carrot",
      "beetroot"            => "beetroot",
      "parsnips"            => "parsnip",
      "parsley-root"        => "parsnip",
      "salsify"             => "root",
      "turnip"              => "turnip",
      "celeriac"            => "celery",
      "courgette"           => "courgette",
      "squash"              => "squash",
      "melons"              => "melon",
      "aubergine"           => "aubergine",
      "physalis"            => "physalis",
      "sweet-corn"          => "sweetcorn",
      "swiss-chard"         => "chard",
      "spinach-and-similar" => "spinach",
      "radish"              => "radish",
      "winter-radish"       => "radish",
      "florence-fennel"     => "fennel",
      "cress"               => "cress",
      "winterpurslane"      => "other",
      "mustard-greens"      => "brassica",
      "artichoke"           => "other",
      "namenia"             => "brassica",
      "catalognapuntarelle" => "lettuce",
    }.freeze

    HERB_SECTION = "herbs"
    FLOWER_SECTION = "flowers"

    def self.scrape
      entries = []

      # Vegetables
      VEGETABLE_CATEGORIES.each do |subcat, crop_type|
        sleep 1
        entries += scrape_section("vegetables", subcat, crop_type)
      end

      # Herbs — single page with all herbs
      sleep 1
      entries += scrape_section_generic("herbs", "herb")

      # Flowers
      sleep 1
      entries += scrape_section_generic("flowers", "flower")

      puts "  Total: #{entries.length}"
      entries.uniq { |e| e[:url] }
    end

    def self.scrape_section(section, subcat, crop_type)
      results = []
      url = "#{BASE}/en/organic-seeds/#{section}/#{subcat}.html"
      doc = CatalogScraper.fetch_page(url)
      return results unless doc

      doc.css("a[href*='/en/organic-seeds/#{section}/#{subcat}/']").each do |link|
        href = link["href"].to_s
        next if href.include?("?") || href.end_with?("/#{subcat}/")

        name = extract_name(link)
        next if name.nil? || name.empty? || name.length > 100 || name.length < 2

        full_url = href.start_with?("http") ? href : "#{BASE}#{href}"
        results << make_entry(name, crop_type, full_url, href)
      end

      puts "  #{subcat}: #{results.length}"
      results
    end

    def self.scrape_section_generic(section, crop_type)
      results = []
      url = "#{BASE}/en/organic-seeds/#{section}.html"
      doc = CatalogScraper.fetch_page(url)
      return results unless doc

      doc.css("a[href*='/en/organic-seeds/#{section}/']").each do |link|
        href = link["href"].to_s
        next if href.include?("?") || href.end_with?("/#{section}/")
        next if href.end_with?(".html") && !href.include?("/#{section}/") # skip nav links

        name = extract_name(link)
        next if name.nil? || name.empty? || name.length > 100 || name.length < 2

        full_url = href.start_with?("http") ? href : "#{BASE}#{href}"
        results << make_entry(name, crop_type, full_url, href)
      end

      # Also check subcategories within herbs/flowers
      doc.css("a[href$='.html']").each do |sublink|
        subhref = sublink["href"].to_s
        next unless subhref.include?("/en/organic-seeds/#{section}/")
        next if subhref == url
        # This is a subcategory page — scrape it too
        sleep 1
        subdoc = CatalogScraper.fetch_page(subhref.start_with?("http") ? subhref : "#{BASE}#{subhref}")
        next unless subdoc
        subdoc.css("a").each do |link|
          href = link["href"].to_s
          next unless href.include?("/en/organic-seeds/#{section}/")
          next if href.include?("?") || href.end_with?(".html")

          name = extract_name(link)
          next if name.nil? || name.empty? || name.length > 100 || name.length < 2

          full_url = href.start_with?("http") ? href : "#{BASE}#{href}"
          results << make_entry(name, crop_type, full_url, href)
        end
      end

      puts "  #{section}: #{results.length}"
      results
    end

    def self.extract_name(link)
      strong = link.css("strong").first
      if strong
        raw = strong.text.strip.gsub(/\A\[/, "").gsub(/\]\z/, "").strip
        strip_type_prefix(raw)
      else
        link.text.strip
      end
    end

    def self.make_entry(name, crop_type, url, href)
      {
        variety_name: name, crop_type: crop_type, crop_subcategory: nil,
        url: url, article_number: extract_sku(href),
        latin_name: nil, description: nil, germination_temp: nil,
        spacing: nil, days_to_maturity: nil, sowing_info: nil,
        frost_tender: nil, direct_sow: nil,
      }
    end

    def self.extract_sku(href)
      href =~ /-([gG]\d+)$/ ? $1.upcase : nil
    end

    PREFIXES = %w[Standard Cherry Wild Cocktail Plum Beef Beefsteak Oxheart Round Oval Elongated].freeze

    def self.strip_type_prefix(name)
      tokens = name.split
      while tokens.length > 1 && PREFIXES.include?(tokens.first)
        tokens.shift
      end
      crop_words = %w[Tomato Pepper Cucumber Lettuce Bean Pea Squash Carrot Onion Brassica Leek]
      while tokens.length > 1 && crop_words.include?(tokens.first)
        tokens.shift
      end
      tokens.join(" ")
    end
  end
end
