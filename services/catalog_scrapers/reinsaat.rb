module CatalogScrapers
  class Reinsaat
    BASE = "https://www.reinsaat.at/shop/EN"

    # Categories to scrape with their crop_type mapping
    CATEGORIES = {
      "beans"           => "bean",
      "peas"            => "pea",
      "cucumbers"       => "cucumber",
      "brassica"        => "brassica",
      "pumpkins_squash" => "squash",
      "swiss_chard"     => "herb",
      "aubergine"       => "other",
      "melons"          => "other",
      "carrots"         => "root",
      "sweet_pepper"    => "pepper",
      "chilli_peppers"  => "pepper",
      "radish"          => "radish",
      "beetroot"        => "root",
      "lettuce"         => "lettuce",
      "celery"          => "herb",
      "spinach"         => "other",
      "tomatoes"        => "tomato",
      "zucchini"        => "squash",
      "onion_garlic"    => "onion",
      "florence_fennel" => "herb",
      "leeks"           => "onion",
      "parsley"         => "herb",
      "parsnips"        => "root",
      "corn"            => "other",
    }.freeze

    def self.scrape
      entries = []

      CATEGORIES.each do |category_slug, crop_type|
        sleep 1 # Be polite
        doc = CatalogScraper.fetch_page("#{BASE}/#{category_slug}/")
        next unless doc

        # Extract product links from category page
        doc.css("a[href*='/shop/EN/#{category_slug}/']").each do |link|
          href = link["href"]
          next if href.nil? || href == "/shop/EN/#{category_slug}/"
          next if href.include?("?") # skip filter/sort links

          name = link.text.strip
          next if name.empty? || name.length > 100

          url = href.start_with?("http") ? href : "https://www.reinsaat.at#{href}"

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

        puts "  #{category_slug}: found #{entries.length} total so far"
      end

      # Deduplicate by URL
      entries.uniq { |e| e[:url] }
    end
  end
end
