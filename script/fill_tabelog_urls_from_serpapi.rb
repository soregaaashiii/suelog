# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

SERPAPI_KEY = ENV["SERPAPI_KEY"]

if SERPAPI_KEY.blank?
  puts "SERPAPI_KEY is missing"
  exit 1
end

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
    num: 5,
    hl: "ja",
    gl: "jp"
  }

  uri.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(uri)
  return nil unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
rescue => e
  puts "SerpApi error: #{e.class} #{e.message}"
  nil
end

def tabelog_shop_url?(url)
  url.to_s.include?("tabelog.com/") && url.to_s.match?(%r{/[^/]+/A\d+/A\d+/\d+/?})
end

def normalize_tabelog_url(url)
  url.to_s.split("?").first.sub(%r{/?$}, "/")
end

updated = 0
skipped = 0
failed = 0

scope = Shop.approved.where(tabelog_url: [nil, ""]).limit(100)

puts "対象店舗数: #{scope.count}"

scope.find_each do |shop|
  query = build_search_query(shop)
  puts "\n検索: #{shop.name}"
  puts query

  result = fetch_google_result(query)

  organic_results = result&.dig("organic_results") || []

  candidate = organic_results
    .map { |r| r["link"] }
    .compact
    .map { |url| normalize_tabelog_url(url) }
    .find { |url| tabelog_shop_url?(url) }

  if candidate.blank?
    puts "  候補なし"
    failed += 1
    sleep 0.3
    next
  end

  affiliate_url = candidate

  shop.update!(
    tabelog_url: candidate,
    tabelog_affiliate_url: affiliate_url,
    tabelog_matched_at: Time.current,
    tabelog_match_method: "serpapi_auto"
  )

  puts "  保存: #{candidate}"
  updated += 1

  sleep 0.3
rescue => e
  puts "  失敗: #{e.class} #{e.message}"
  skipped += 1
end

puts "\n完了"
puts "更新: #{updated}"
puts "候補なし: #{failed}"
puts "失敗: #{skipped}"
