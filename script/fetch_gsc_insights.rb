# /Users/kawamuratakuya/dev/suelog/script/fetch_gsc_insights.rb
# frozen_string_literal: true

require "csv"
require "fileutils"
require "google/apis/searchconsole_v1"
require "googleauth"

SITE_URL = "sc-domain:suelog.jp"

client_id = ENV.fetch("GOOGLE_CLIENT_ID").strip
client_secret = ENV.fetch("GOOGLE_CLIENT_SECRET").strip
refresh_token = ENV.fetch("GOOGLE_REFRESH_TOKEN").strip

authorizer =
  Google::Auth::UserRefreshCredentials.new(
    client_id: client_id,
    client_secret: client_secret,
    scope: [
      "https://www.googleapis.com/auth/webmasters.readonly"
    ],
    refresh_token: refresh_token
  )

service = Google::Apis::SearchconsoleV1::SearchConsoleService.new
service.authorization = authorizer

output_dir = Rails.root.join("tmp/insights")
FileUtils.mkdir_p(output_dir)

queries_csv =
  output_dir.join("gsc_queries.csv")

query_pages_csv =
  output_dir.join("gsc_query_pages.csv")

start_date = 28.days.ago.to_date.to_s
end_date = Date.yesterday.to_s

request =
  Google::Apis::SearchconsoleV1::SearchAnalyticsQueryRequest.new(
    start_date: start_date,
    end_date: end_date,
    dimensions: %w[query page],
    row_limit: 25000
  )

response =
  service.query_searchanalytic(
    SITE_URL,
    request
  )

rows = response.rows || []

query_summary = Hash.new do |h, k|
  h[k] = {
    clicks: 0,
    impressions: 0,
    ctr_sum: 0.0,
    position_sum: 0.0,
    count: 0
  }
end

CSV.open(query_pages_csv, "w") do |csv|
  csv << [
    "query",
    "page",
    "clicks",
    "impressions",
    "ctr",
    "position"
  ]

  rows.each do |row|
    query = row.keys[0]
    page = row.keys[1]

    csv << [
      query,
      page,
      row.clicks,
      row.impressions,
      row.ctr,
      row.position
    ]

    summary = query_summary[query]

    summary[:clicks] += row.clicks.to_i
    summary[:impressions] += row.impressions.to_i
    summary[:ctr_sum] += row.ctr.to_f
    summary[:position_sum] += row.position.to_f
    summary[:count] += 1
  end
end

CSV.open(queries_csv, "w") do |csv|
  csv << [
    "query",
    "clicks",
    "impressions",
    "ctr",
    "position"
  ]

  query_summary.each do |query, summary|
    count = summary[:count].to_i

    csv << [
      query,
      summary[:clicks],
      summary[:impressions],
      (summary[:ctr_sum] / count).round(4),
      (summary[:position_sum] / count).round(2)
    ]
  end
end

puts "Saved:"
puts queries_csv
puts query_pages_csv