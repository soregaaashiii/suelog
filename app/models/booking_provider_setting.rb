class BookingProviderSetting < ApplicationRecord
  PROVIDERS = {
    "all" => "すべてのサービス",
    "tabelog" => "食べログ",
    "hotpepper" => "ホットペッパー",
    "gurunavi" => "ぐるなび",
    "custom" => "その他の予約リンク"
  }.freeze

  validates :provider, inclusion: { in: PROVIDERS.keys }, uniqueness: true
  validates :hidden, inclusion: { in: [true, false] }

  def self.hidden_providers
    where(hidden: true).pluck(:provider)
  end
end
