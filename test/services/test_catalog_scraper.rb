require_relative "../test_helper"
require_relative "../../services/catalog_scraper"

class TestCatalogScraper < GardenTest
  def test_fetch_page_returns_nokogiri_doc
    # Skip if no network (CI)
    skip "Network required" unless system("ping -c 1 -t 2 reinsaat.at > /dev/null 2>&1")
    doc = CatalogScraper.fetch_page("https://www.reinsaat.at/shop/EN/tomatoes/")
    refute_nil doc
    assert_kind_of Nokogiri::HTML::Document, doc
  end

  def test_fetch_page_returns_nil_on_bad_url
    # A completely invalid host should fail gracefully
    result = CatalogScraper.fetch_page("https://this-host-does-not-exist-at-all.invalid/", retries: 0)
    assert_nil result
  end

  def test_scrape_supplier_saves_to_db
    skip "Network required" unless system("ping -c 1 -t 2 reinsaat.at > /dev/null 2>&1")
    CatalogScraper.scrape_supplier!("reinsaat")
    count = SeedCatalogEntry.where(supplier: "reinsaat").count
    assert count > 10, "Expected at least 10 Reinsaat entries, got #{count}"
  end
end
