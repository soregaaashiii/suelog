# frozen_string_literal: true

require "googleauth"
require "googleauth/stores/file_token_store"
require "fileutils"

client_id = ENV.fetch("GOOGLE_CLIENT_ID").strip
client_secret = ENV.fetch("GOOGLE_CLIENT_SECRET").strip

scope = "https://www.googleapis.com/auth/webmasters.readonly"

client = Signet::OAuth2::Client.new(
  authorization_uri: "https://accounts.google.com/o/oauth2/auth",
  token_credential_uri: "https://oauth2.googleapis.com/token",
  client_id: client_id,
  client_secret: client_secret,
  scope: scope,
  redirect_uri: "urn:ietf:wg:oauth:2.0:oob"
)

auth_url = client.authorization_uri(
  access_type: "offline",
  prompt: "consent"
).to_s

puts
puts "以下のURLをブラウザで開いて認証してください:"
puts
puts auth_url
puts
puts "表示された認可コードを貼り付けてEnter:"
print "> "

code = STDIN.gets&.strip

if code.nil? || code.empty?
  abort "認可コードが空です"
end

client.code = code
token = client.fetch_access_token!

puts
puts "取得成功"
puts
puts "GOOGLE_REFRESH_TOKEN="
puts token["refresh_token"]
puts
puts "この値をRenderの GOOGLE_REFRESH_TOKEN に設定してください"
