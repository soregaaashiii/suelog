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

def normalize_search_text(text)
  text.to_s
      .unicode_normalize(:nfkc)
      .gsub(/[[:space:]]+/, " ")
      .strip
end

def short_shop_name(name)
  normalize_search_text(name)
    .gsub(/【[^】]*】/, "")
    .gsub(/（[^）]*）/, "")
    .gsub(/\([^)]*\)/, "")
    .gsub(/大阪梅田店\z/, "")
    .gsub(/梅田店\z/, "")
    .gsub(/大阪店\z/, "")
    .gsub(/本店\z/, "")
    .gsub(/店\z/, "")
    .strip
end

def cleaned_address(address)
  normalize_search_text(address)
    .gsub(/日本、?/, "")
    .gsub(/〒?\d{3}-?\d{4}/, "")
    .gsub(/大阪府/, "")
    .strip
end

def address_town(address)
  text = cleaned_address(address)

  match = text.match(/大阪市[^市区町村]*区([^0-9０-９\s]+?)(?:\d|[０-９]|丁目|番|号|$)/)
  return match[1] if match.present?

  nil
end

def build_search_queries(shop)
  name = normalize_search_text(shop.name)
  short_name = short_shop_name(shop.name)
  town = address_town(shop.address)

  queries = []

  queries << [
    "site:tabelog.com",
    name,
    "大阪",
    "梅田"
  ].join(" ")

  if town.present?
    queries << [
      "site:tabelog.com",
      name,
      "大阪市北区",
      town
    ].join(" ")

    queries << [
      name,
      town,
      "食べログ"
    ].join(" ")
  end

  if short_name.present? && short_name != name
    queries << [
      "site:tabelog.com",
      short_name,
      "大阪",
      "梅田"
    ].join(" ")

    queries << [
      short_name,
      "梅田",
      "食べログ"
    ].join(" ")
  end

  queries.uniq
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

def normalize_tabelog_url(url)
  url.to_s
     .gsub("s.tabelog.com", "tabelog.com")
     .sub(%r{/dtlrvwlst.*$}, "/")
     .sub(%r{/dtlmenu.*$}, "/")
     .sub(%r{/dtlmap/?$}, "/")
     .sub(%r{/photo/?$}, "/")
end

def valid_tabelog_shop_url?(url)
  link = url.to_s

  link.match?(%r{https?://(?:s\.)?tabelog\.com/.+/\d+/?}) &&
    !link.include?("/keywords/") &&
    !link.include?("/rstLst/") &&
    !link.include?("/rank")
end

def candidate_score(shop, result)
  score = 0

  title = result["title"].to_s
  snippet = result["snippet"].to_s
  link = result["link"].to_s

  normalized_title = normalize_search_text(title).downcase
  normalized_name = normalize_search_text(shop.name).downcase
  normalized_short_name = short_shop_name(shop.name).downcase
  town = address_town(shop.address)

  score += 50 if normalized_name.present? && normalized_title.include?(normalized_name)
  score += 35 if normalized_short_name.present? && normalized_title.include?(normalized_short_name)
  score += 20 if town.present? && (title.include?(town) || snippet.include?(town))
  score += 15 if title.include?("梅田") || snippet.include?("梅田")
  score += 15 if title.include?("大阪") || snippet.include?("大阪")
  score += 10 if link.include?("/osaka/")

  score
end

def best_tabelog_result(shop, organic_results)
  candidates = organic_results.select { |r| valid_tabelog_shop_url?(r["link"]) }

  candidates
    .map { |r| [r, candidate_score(shop, r)] }
    .select { |_r, score| score >= 50 }
    .max_by { |_r, score| score }
end

CSV.open(output_path, "w") do |csv|
  csv << [
    "name",
    "tabelog_url",
    "affiliate_url",
    "status"
  ]

  Shop.where(tabelog_url: nil)
      .where(approved: true)
      .where.not(name: [nil, ""])
      .find_each do |shop|

    queries = build_search_queries(shop)

    matched_result = nil
    matched_score = nil
    matched_query = nil

    queries.each do |query|
      result = fetch_google_result(query)

      organic_results = result&.dig("organic_results") || []

      result_and_score = best_tabelog_result(shop, organic_results)

      if result_and_score.present?
        matched_result, matched_score = result_and_score
        matched_query = query
        break
      end

      sleep 1
    end

    if matched_result.present?
      tabelog_url = normalize_tabelog_url(matched_result["link"])

      affiliate_url =
        "https://ck.jp.ap.valuecommerce.com/servlet/referral?sid=3769275&pid=892611116&vc_url=#{CGI.escape(tabelog_url)}"

      shop.update!(
        tabelog_url: tabelog_url,
        tabelog_affiliate_url: affiliate_url,
        tabelog_matched_at: Time.current,
        tabelog_match_method: "serpapi_auto_score_#{matched_score}"
      )

      csv << [
        shop.name,
        tabelog_url,
        affiliate_url,
        "saved"
      ]

      puts "Saved: #{shop.name} score=#{matched_score} query=#{matched_query}"
    else
      csv << [
        shop.name,
        nil,
        nil,
        "not_found"
      ]

      puts "Not found: #{shop.name}"
    end

    sleep 1
  end
end

puts "----------------------"
puts "Output: #{output_path}"