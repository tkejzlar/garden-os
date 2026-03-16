module CatalogScrapers
  class Loukykvet
    BASE = "https://www.loukykvet.cz"

    # Czech seed categories → crop_type
    # Loukykvet is primarily a flower/meadow seed specialist
    # but also carries herbs and some vegetables
    CATEGORIES = {
      "bazalka"    => "herb",    # basil
      "levandule"  => "herb",    # lavender
      "rebricek"   => "herb",    # yarrow (Achillea) — herb/flower
      "mesicek"    => "herb",    # marigold (Calendula) — medicinal herb
      "salvej"     => "herb",    # sage
      "sater"      => "herb",    # savory
      "rericha"    => "herb",    # rocket/arugula
      "laskavec"   => "other",   # amaranth
      "slunecnice" => "other",   # sunflower
      "mak"        => "other",   # poppy
      "hrachor"    => "flower",  # sweet pea
      "krasenka"   => "flower",  # cosmos
      "cinie"      => "flower",  # zinnia
      "hledik"     => "flower",  # snapdragon
      "chrpa"      => "flower",  # cornflower
      "astra"      => "flower",  # aster
      "ostrozka-stracka" => "flower",  # larkspur
      "fiala-letni" => "flower", # annual pansy
      "statice"    => "flower",  # sea lavender
      "slamenka"   => "flower",  # everlasting/strawflower
      "naprstnik"  => "flower",  # foxglove
      "nestarec"   => "flower",  # ageratum
      "nevadlec"   => "flower",  # nigella/love-in-a-mist
      "orlicek"    => "flower",  # columbine
      "pomnenka"   => "flower",  # forget-me-not
      "rudbekie"   => "flower",  # rudbeckia
      "sluncovka"  => "flower",  # heliopsis
      "verbena"    => "flower",  # verbena
      "zvonek"     => "flower",  # bellflower
      "afrikan"    => "flower",  # tagetes / African marigold
      "mesicnice"  => "flower",  # moonflower/lunaria
      "okrasne-travy" => "other", # ornamental grasses
      "echinacea"  => "herb",    # echinacea
    }.freeze

    def self.scrape
      entries = []

      CATEGORIES.each do |category_slug, crop_type|
        sleep 1
        url = "#{BASE}/obchod/semena/#{category_slug}"
        doc = CatalogScraper.fetch_page(url)
        next unless doc

        count_before = entries.length

        # Product links are /obchod/[numeric-id]-[slug]
        doc.css("a[href*='/obchod/']").each do |link|
          href = link["href"]
          next unless href
          # Match numeric-id product URLs like /obchod/1234-bazalka-dark-opal
          next unless href =~ %r{\A/obchod/\d+-[a-z0-9-]+\z}

          full_url = href.start_with?("http") ? href : "#{BASE}#{href}"

          # Try to get name from link text (not image alt)
          # Strip whitespace and skip empty/nav items
          name = link.text.strip
          next if name.empty? || name.length > 150
          # Skip cart/navigation text
          next if name =~ /\A(košík|semena|obchod|zobrazit|přidat|detail)\z/i

          entries << {
            variety_name:     name,
            crop_type:        crop_type,
            crop_subcategory: category_slug,
            url:              full_url,
            article_number:   extract_id(href),
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

        puts "  #{category_slug}: #{entries.length - count_before} varieties"
      end

      entries.uniq { |e| e[:url] }
    end

    # Extract numeric ID from URL slug: /obchod/4633-bazalka-cinamonette → "4633"
    def self.extract_id(href)
      if href =~ %r{/obchod/(\d+)-}
        $1
      end
    end
  end
end
