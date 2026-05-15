# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

SERPAPI_KEY = ENV["SERPAPI_KEY"]

if SERPAPI_KEY.blank?
  puts "SERPAPI_KEY is missing"
  exit 1
end

def address_town_hint(address)
  normalized_address = address.to_s
                              .unicode_normalize(:nfkc)
                              .gsub("日本、〒", "")
                              .gsub(/\d{3}-?\d{4}/, "")
                              .strip

  match = normalized_address.match(/大阪府大阪市[^区]+区(.+?)(?:\d|丁目|番|号|[-−ー―])/)
  return match[1].to_s.strip if match && match[1].present?

  match = normalized_address.match(/大阪市[^区]+区(.+?)(?:\d|丁目|番|号|[-−ー―])/)
  return match[1].to_s.strip if match && match[1].present?

  nil
end

def build_search_query(shop)
  town_hint = address_town_hint(shop.address)

  [
    "site:tabelog.com/osaka/",
    shop.name,
    town_hint,
    "大阪",
    "食べログ"
  ].compact.join(" ")
end

def fetch_google_result(query)
  uri = URI("https://serpapi.com/search.json")

  params = {
    q: query,
    api_key: SERPAPI_KEY,
    engine: "google",
    num: 10,
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

def normalize_name(text)
  text.to_s
      .downcase
      .unicode_normalize(:nfkc)
      .gsub(/[[:space:]]+/, "")
      .gsub(/[・･]/, "")
      .gsub(/[“”"'`]/, "")
      .gsub(/（.*?）|\(.*?\)/, "")
      .gsub(/梅田店|大阪駅前店|大阪梅田店|お初天神店|東通り店|阪急東通り店|北新地店|茶屋町店|兎我野町店|本店/, "")
      .gsub(/大阪駅前第\dビル店/, "")
end

def title_matches?(shop, title)
  normalized_shop_name = normalize_name(shop.name)
  normalized_title = normalize_name(title)

  return false if normalized_shop_name.blank? || normalized_title.blank?

  normalized_title.include?(normalized_shop_name) ||
    normalized_shop_name.include?(normalized_title)
end

def address_matches?(shop, snippet)
  address = shop.address.to_s
  snippet = snippet.to_s

  ward =
    if address.include?("北区")
      "北区"
    elsif address.include?("中央区")
      "中央区"
    elsif address.include?("福島区")
      "福島区"
    elsif address.include?("西区")
      "西区"
    end

  return true if ward.blank?

  snippet.include?(ward) || snippet.include?("大阪")
end

def matched_tabelog_result(shop, organic_results)
  organic_results.find do |result|
    url = normalize_tabelog_url(result["link"])

    next false if url.blank?
    next false unless tabelog_shop_url?(url)
    next false unless title_matches?(shop, result["title"])
    next false unless address_matches?(shop, result["snippet"])

    true
  end
end

def suspect_tabelog_result(shop, organic_results)
  organic_results.find do |result|
    url = normalize_tabelog_url(result["link"])

    next false if url.blank?
    next false unless tabelog_shop_url?(url)
    next false unless address_matches?(shop, result["snippet"])

    true
  end
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

  matched_result = matched_tabelog_result(shop, organic_results)
  suspect_result = matched_result.presence || suspect_tabelog_result(shop, organic_results)

  candidate = normalize_tabelog_url(suspect_result&.dig("link"))

  if candidate.blank?
    puts "  候補なし"
    failed += 1
    sleep 0.3
    next
  end

  match_method =
    if matched_result.present?
      "serpapi_auto"
    else
      "serpapi_suspect"
    end

  affiliate_url = candidate

  shop.update!(
    tabelog_url: candidate,
    tabelog_affiliate_url: affiliate_url,
    tabelog_matched_at: Time.current,
    tabelog_match_method: match_method
  )

  puts "  保存: #{candidate} / #{match_method}"
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
