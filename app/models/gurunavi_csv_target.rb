class GurunaviCsvTarget < ApplicationRecord
  belongs_to :gurunavi_csv_batch
  has_many :matches, class_name: "GurunaviCsvMatch", dependent: :destroy
  serialize :shop_snapshot, coder: JSON
  include AffiliateRegistrationTarget
  def self.registration_provider_label = "ぐるなび"
  CLASSIFICATIONS = { "bulk"=>"一括登録候補", "review"=>"要確認", "unmatched"=>"CSV内に候補なし", "registered"=>"登録済み", "conflict"=>"競合" }.freeze
end
