class GurunaviCsvTarget < ApplicationRecord
  belongs_to :gurunavi_csv_batch
  has_many :matches, class_name: "GurunaviCsvMatch", dependent: :destroy
  serialize :shop_snapshot, coder: JSON
  scope :registered, -> {
    where("gurunavi_csv_targets.state IN ('applied', 'skipped', 'rollback_conflict') OR (gurunavi_csv_targets.classification = 'registered' AND gurunavi_csv_targets.state != 'rolled_back') OR EXISTS (SELECT 1 FROM gurunavi_csv_matches WHERE gurunavi_csv_matches.gurunavi_csv_target_id = gurunavi_csv_targets.id AND gurunavi_csv_matches.state IN ('applied', 'skipped', 'rollback_conflict'))")
  }
  scope :held, -> { where(state: "held").where.not(id: registered.select(:id)) }
  scope :excluded, -> { where(state: "excluded").where.not(id: registered.select(:id)) }
  scope :url_conflicts, -> {
    legacy = GurunaviCsvMatch.where(state: "conflict", reason: "同じぐるなびURLが他店舗に登録済みです").select(:gurunavi_csv_target_id)
    where(state: "url_conflict").or(where(id: legacy)).where.not(state: [ "excluded", "held" ]).where.not(id: registered.select(:id))
  }
  scope :unregistered, -> { where.not(id: registered.select(:id)).where.not(state: [ "excluded", "held" ]).where.not(id: url_conflicts.select(:id)) }
  CLASSIFICATIONS = { "bulk"=>"一括登録候補", "review"=>"要確認", "unmatched"=>"CSV内に候補なし", "registered"=>"登録済み", "conflict"=>"競合" }.freeze
end
