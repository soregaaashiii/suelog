class GurunaviCsvRow < ApplicationRecord
  belongs_to :gurunavi_csv_batch
  has_many :matches, class_name: "GurunaviCsvMatch", dependent: :destroy
  serialize :raw_fields, coder: JSON
  CLASSIFICATIONS = { "bulk"=>"一括登録候補", "review"=>"要確認", "unmatched"=>"未一致", "registered"=>"登録済み", "conflict"=>"競合", "invalid"=>"不正・欠損行", "out_of_scope"=>"試行・エリア対象外" }.freeze
end
