# frozen_string_literal: true

require "csv"
require "net/http"
require "json"
require "uri"
require "cgi"

SERPAPI_KEY = ENV["SERPAPI_KEY"]

if SERPAPI_KEY.blank?
  puts "SERPAPI_KEY is missing"
  exit
end

output_path = Rails.root.join("tmp/tabelog_candidates.csv")

def build_search_query(shop)
  [
    "site:tabelog.com",
    shop.name,
    shop.address.to_s.gsub("日本、〒", "")
  ].join(" ")
end

def fetch_google_result(query)
  uri = URI("https://serpapi.com/search.json")

  params = {
    q: query,
    api_key: SERPAPI_KEY,
    engine: "google",
    num: 5
  }

  uri.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(uri)

  return nil unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

CSV.open(output_path, "w") do |csv|
  csv << [
    "name",
    "tabelog_url",
    "affiliate_url"
  ]

  Shop.where(tabelog_url: nil)
      .where(approved: true)
      .where.not(name: [nil, ""])
      .find_each do |shop|

    query = build_search_query(shop)

    result = fetch_google_result(query)

    organic_results = result&.dig("organic_results") || []

    tabelog_result = organic_results.find do |r|
      link = r["link"].to_s

      link.match?(%r{https?://(?:s\.)?tabelog\.com/.+/\d+/?}) &&
        !link.include?("/keywords/") &&
        !link.include?("/rstLst/") &&
        !link.include?("/rank")
    end

    if tabelog_result.present?
      tabelog_url = tabelog_result["link"]

      tabelog_url = tabelog_url.gsub("s.tabelog.com", "tabelog.com")
      tabelog_url = tabelog_url.sub(%r{/dtlrvwlst.*$}, "/")
      tabelog_url = tabelog_url.sub(%r{/dtlmenu.*$}, "/")
      tabelog_url = tabelog_url.sub(%r{/dtlmap/?$}, "/")
      tabelog_url = tabelog_url.sub(%r{/photo/?$}, "/")

      affiliate_url =
        "https://ck.jp.ap.valuecommerce.com/servlet/referral?sid=3769275&pid=892611116&vc_url=#{CGI.escape(tabelog_url)}"

      csv << [
        shop.name,
        tabelog_url,
        affiliate_url
      ]

      puts "Found: #{shop.name}"
    else
      puts "Not found: #{shop.name}"
    end

    sleep 1
  end
end

puts "----------------------"
puts "Output: #{output_path}"