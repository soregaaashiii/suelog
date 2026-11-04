class GurunaviCsvMatch < ApplicationRecord
  belongs_to :gurunavi_csv_target, optional: true
  belongs_to :gurunavi_csv_row
  serialize :shop_snapshot, coder: JSON
  serialize :before_values, coder: JSON
  serialize :after_values, coder: JSON
  STATES = { "pending"=>"未確認", "confirmed"=>"同一店舗と確認済み", "excluded"=>"別店舗として除外", "held"=>"保留", "applied"=>"登録完了", "skipped"=>"登録済み・スキップ", "conflict"=>"競合・未更新", "rolled_back"=>"取り消し済み", "rollback_conflict"=>"取り消し競合" }.freeze
end
