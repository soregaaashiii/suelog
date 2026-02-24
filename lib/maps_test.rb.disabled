require "httparty"

api_key = ENV["GOOGLE_MAPS_API_KEY"]
abort "GOOGLE_MAPS_API_KEY が空です（.envが読めてない）" if api_key.to_s.strip.empty?

query = "梅田 喫煙可"
url = "https://maps.googleapis.com/maps/api/place/textsearch/json"

response = HTTParty.get(url, query: {
  query: query,
  key: api_key,
  language: "ja"
})

puts response.body

