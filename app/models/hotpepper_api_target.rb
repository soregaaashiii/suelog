class HotpepperApiTarget < ApplicationRecord
  belongs_to :hotpepper_api_batch
  has_many :matches, class_name: "HotpepperApiMatch", dependent: :destroy
  serialize :shop_snapshot, coder: JSON
  include AffiliateRegistrationTarget
  def self.registration_provider_label = "ホットペッパー"
  CLASSIFICATIONS = { "bulk"=>"一括登録候補", "review"=>"要確認", "unmatched"=>"API検索で候補なし", "registered"=>"登録済み", "conflict"=>"競合" }.freeze
end
