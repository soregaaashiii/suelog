require "net/http"
require "json"
require "nokogiri"

module RestaurantUrlSearch
  class DetailReader
    MAX_BYTES = 2 * 1024 * 1024
    TYPES = %w[Restaurant FoodEstablishment CafeOrCoffeeShop BarOrPub].freeze

    def call(url, provider)
      current = provider.canonical_url(url)
      return unless current
      3.times do
        uri = URI(current)
        body = +""
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5) do |http|
          request = Net::HTTP::Get.new(uri.request_uri, "User-Agent" => "SuelogStoreVerification/1.0", "Accept" => "text/html")
          http.request(request) do |res|
            if res.is_a?(Net::HTTPSuccess)
              res.read_body do |chunk|
                body << chunk
                raise IOError if body.bytesize > MAX_BYTES
              end
            end
          end
        end
        if response.is_a?(Net::HTTPRedirection)
          destination = URI.join(current, response["location"].to_s).to_s
          # A redirect to another store may indicate relocation: never confirm it.
          return unless provider.canonical_url(destination) == current
          next
        end
        return unless response.is_a?(Net::HTTPSuccess)
        return parse(body, current, provider)
      end
      nil
    rescue URI::InvalidURIError, JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      nil
    end

    def parse(body, url, provider)
      doc = Nokogiri::HTML(body)
      records = doc.css('script[type="application/ld+json"]').flat_map do |script|
        begin
          flatten(JSON.parse(script.text))
        rescue JSON::ParserError
          []
        end
      end.select { |item| (Array(item["@type"]) & TYPES).any? }
      restaurants_present = records.present?
      records.select! { |item| item["url"].blank? || provider.canonical_url(item["url"]) == url }
      return if restaurants_present && records.empty?
      return if records.size > 1
      record = records.first || {}
      fields = doc.css("tr").each_with_object({}) do |row, result|
        label = row.at_css("th")&.text.to_s.strip
        result[label] = row.at_css("td")&.text.to_s.strip if label.present?
      end
      address = record["address"]
      address = [address["addressRegion"], address["addressLocality"], address["streetAddress"]].compact.join if address.is_a?(Hash)
      page_text = doc.at_css("main")&.text || doc.at_css("body")&.text.to_s
      {
        name: record["name"].presence || fields["店名"] || doc.at_css("h1")&.text.to_s.strip,
        address: address.presence || fields["住所"],
        phone: record["telephone"].presence || fields["電話番号"] || fields["お問い合わせ"],
        relocated: page_text.match?(/移転前|移転しました|移転しています|閉店しました|閉店しています|営業を終了/)
      }
    end

    private
    def flatten(value)
      case value
      when Array then value.flat_map { |item| flatten(item) }
      when Hash then [value] + flatten(value["@graph"])
      else []
      end
    end
  end
end
