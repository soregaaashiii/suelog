require "uri"
require "cgi"

class BackfillGurunaviAffiliateUrls < ActiveRecord::Migration[8.1]
  class MigrationShop < ActiveRecord::Base
    self.table_name = "shops"
  end

  def up
    MigrationShop.where(gurunavi_affiliate_url: [nil, ""]).where.not(gurunavi_url: [nil, ""]).find_each do |shop|
      begin
        uri = URI.parse(shop.gurunavi_url.strip)
        next unless uri.is_a?(URI::HTTP) && uri.host == "r.gnavi.co.jp" &&
          uri.path.match?(%r{\A/[a-zA-Z0-9]+/?\z}) && uri.userinfo.nil? && uri.port == uri.default_port
        url = "https://click.linksynergy.com/deeplink?id=*wLoiMUEEgU&mid=47268&murl=" + CGI.escape(uri.to_s)
        MigrationShop.where(id: shop.id, gurunavi_url: shop.gurunavi_url, gurunavi_affiliate_url: [nil, ""]).update_all(gurunavi_affiliate_url: url)
      rescue URI::InvalidURIError
        # Keep invalid or not-found source URLs unchanged for admin review.
        next
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
