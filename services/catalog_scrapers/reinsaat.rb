module CatalogScrapers
  class Reinsaat
    BASE = "https://www.reinsaat.at/shop/EN"

    # All vegetable/herb/flower categories with correct slugs
    CATEGORIES = {
      "beans"                       => "bean",
      "peas"                        => "pea",
      "cucumbers"                   => "cucumber",
      "brassica"                    => "brassica",
      "pumpkins_squash"             => "squash",
      "swiss_chard"                 => "chard",
      "aubergine_eggplants"         => "aubergine",
      "melons"                      => "melon",
      "carrots"                     => "carrot",
      "sweet_pepper"                => "pepper",
      "chilli_peppers_chill"        => "pepper",
      "radish"                      => "radish",
      "beetroot"                    => "beetroot",
      "lettuce"                     => "lettuce",
      "celery"                      => "celery",
      "spinach"                     => "spinach",
      "tomatoes"                    => "tomato",
      "zucchini_courgette"          => "courgette",
      "onion_garlic"                => "onion",
      "florence_fennel"             => "fennel",
      "leeks"                       => "leek",
      "parsley"                     => "herb",
      "parsley_root"                => "parsnip",
      "parsnips"                    => "parsnip",
      "corn"                        => "sweetcorn",
      "garden_cress"                => "cress",
      "black_salsify"               => "salsify",
      "potatoes"                    => "potato",
      "culinary_and_aromatic_herbs" => "herb",
      "flowers_and_herbs"           => "flower",
      "wild_flowers_seeds"          => "flower",
      "new_varieties_2026"          => nil,  # mixed — detect from subcategory
      "winter_harvest"              => nil,
      "colourful_mixes"             => "other",
    }.freeze

    def self.scrape
      entries = []

      CATEGORIES.each do |category_slug, default_crop_type|
        sleep 1
        doc = CatalogScraper.fetch_page("#{BASE}/#{category_slug}/")
        next unless doc

        # Broader link matching — grab any link that goes deeper into this category
        doc.css("a").each do |link|
          href = link["href"].to_s
          # Must be a product link within this category (contains the slug and goes one level deeper)
          next unless href.include?("/shop/EN/#{category_slug}/")
          next if href.end_with?("/#{category_slug}/") # skip self-link
          next if href.include?("?") # skip filter/sort
          next if href.include?("#") # skip anchors

          name = link.text.strip
          next if name.empty? || name.length > 100 || name.length < 2
          # Skip navigation-like text
          next if name.match?(/^(Home|Back|Next|Previous|Show|Filter|Sort|All|Page|\d+)$/i)

          url = href.start_with?("http") ? href : "https://www.reinsaat.at#{href}"
          crop_type = default_crop_type || guess_crop_type(name, category_slug)

          entries << {
            variety_name:     name,
            crop_type:        crop_type,
            crop_subcategory: nil,
            url:              url,
            article_number:   nil,
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

        puts "  #{category_slug}: #{entries.length} total so far"
      end

      # Deduplicate by URL
      entries.uniq { |e| e[:url] }
    end

    def self.guess_crop_type(name, category)
      n = name.downcase
      return "tomato" if n.include?("tomat")
      return "pepper" if n.include?("pepper") || n.include?("chilli") || n.include?("paprik")
      return "lettuce" if n.include?("lettuc") || n.include?("salad")
      return "herb" if n.include?("basil") || n.include?("dill") || n.include?("parsley")
      "other"
    end
  end
end
