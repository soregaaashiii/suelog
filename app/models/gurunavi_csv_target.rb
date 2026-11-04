class GurunaviCsvTarget < ApplicationRecord
  belongs_to :gurunavi_csv_batch
  has_many :matches, class_name: "GurunaviCsvMatch", dependent: :destroy
  serialize :shop_snapshot, coder: JSON
  scope :registered, -> {
    where("gurunavi_csv_targets.state IN ('applied', 'skipped', 'rollback_conflict') OR (gurunavi_csv_targets.classification = 'registered' AND gurunavi_csv_targets.state != 'rolled_back') OR EXISTS (SELECT 1 FROM gurunavi_csv_matches WHERE gurunavi_csv_matches.gurunavi_csv_target_id = gurunavi_csv_targets.id AND gurunavi_csv_matches.state IN ('applied', 'skipped', 'rollback_conflict'))")
  }
  scope :unregistered, -> { where.not(id: registered.select(:id)) }
  CLASSIFICATIONS = { "bulk"=>"一括登録候補", "review"=>"要確認", "unmatched"=>"CSV内に候補なし", "registered"=>"登録済み", "conflict"=>"競合" }.freeze
end
