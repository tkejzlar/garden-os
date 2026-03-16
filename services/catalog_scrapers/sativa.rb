module CatalogScrapers
  class Sativa
    BASE = "https://www.sativa.bio"

    # Subcategory pages → crop_type mapping
    CATEGORIES = {
      "tomatoes"               => "tomato",
      "pepperschillies"        => "pepper",
      "cucumbers"              => "cucumber",
      "lettuces-lactuca"       => "lettuce",
      "beans"                  => "bean",
      "broad-beans"            => "bean",
      "peas"                   => "pea",
      "pumpkinssquashes"       => "squash",
      "courgettezucchini"      => "squash",
      "carrots"                => "root",
      "beetroot"               => "root",
      "radish"                 => "radish",
      "radish-small"           => "radish",
      "onion-seeds"            => "onion",
      "leek"                   => "onion",
      "broccoli"               => "brassica",
      "cauliflower"            => "brassica",
      "red-cabbage"            => "brassica",
      "white-cabbage"          => "brassica",
      "savoy-cabbage"          => "brassica",
      "brussels-sprouts"       => "brassica",
      "kale"                   => "brassica",
      "kohlrabi"               => "brassica",
      "asian-brassicas"        => "brassica",
      "chinese-cabbage"        => "brassica",
      "spinach"                => "other",
      "chard"                  => "herb",
      "leaf-beet"              => "herb",
      "fennel"                 => "herb",
      "celeriac"               => "root",
      "field-salad"            => "lettuce",
      "endives"                => "lettuce",
      "aubergines-eggplants"   => "other",
      "melons"                 => "other",
      "parsnip"                => "root",
      "maize"                  => "other",
      "scorzonera"             => "root",
      "purple-salsify"         => "root",
      "turnip"                 => "root",
      "rutabagaswede"          => "root",
      "artichokes"             => "other",
      "cape-gooseberry"        => "other",
      "edamame-soy-bean"       => "bean",
    }.freeze

    def self.scrape
      entries = []

      CATEGORIES.each do |subcategory, crop_type|
        scrape_category(subcategory, crop_type, entries)
      end

      entries.uniq { |e| e[:url] }
    end

    def self.scrape_category(subcategory, crop_type, entries)
      page = 1
      loop do
        sleep 1
        url = "#{BASE}/en/vegetables/#{subcategory}"
        url += "?p=#{page}" if page > 1

        doc = CatalogScraper.fetch_page(url)
        break unless doc

        count_before = entries.length

        # Product links: https://www.sativa.bio/en/[variety-name]-[code]
        # They appear as <a> tags inside product containers
        # Variety names are in <h3> tags inside links, or as link text
        doc.css("a[href]").each do |link|
          href = link["href"]
          next unless href

          # Product URLs look like https://www.sativa.bio/en/amish-pasta-tomatoes-for-processing-prospecierara-to88
          # Full absolute URL ending with a code like -to88, -pe12, -cu5, etc.
          # Skip anchor-only links (larger quantities forms)
          next if href.include?("#")
          next unless href =~ %r{\Ahttps://www\.sativa\.bio/en/[a-z0-9][a-z0-9-]+-[a-z]{2,4}\d+\z}

          full_url = href

          # Extract name from <h3> inside link, or link text
          h3 = link.css("h3").first
          name = h3 ? h3.text.strip : link.text.strip
          next if name.empty? || name.length > 150
          next if name =~ /\A[\s\d€\.]+\z/ # skip price-only text

          # Clean up name: remove trailing " - Type Description" suffixes sometimes present
          name = name.split(" - ").first.strip if name.include?(" - ")

          entries << {
            variety_name:     name,
            crop_type:        crop_type,
            crop_subcategory: nil,
            url:              full_url,
            article_number:   extract_code(href),
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

        added = entries.length - count_before

        # Check for next page link (absolute or relative URLs)
        next_page_url = "#{BASE}/en/vegetables/#{subcategory}?p=#{page + 1}"
        has_next = doc.css("a").any? { |a| a["href"].to_s.include?("?p=#{page + 1}") } ||
                   doc.css("a.next, a[aria-label='Next']").any?

        # Also check if we actually got new products — if not, stop
        break if added == 0 || !has_next
        page += 1
        break if page > 20 # safety cap
      end

      puts "  #{subcategory}: #{entries.select { |e| e[:crop_type] == crop_type }.length} varieties total"
    end

    def self.extract_code(href)
      href.split("-").last
    end
  end
end
