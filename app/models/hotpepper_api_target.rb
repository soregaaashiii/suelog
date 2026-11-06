class HotpepperApiTarget < ApplicationRecord
  belongs_to :hotpepper_api_batch
  has_many :matches, class_name: "HotpepperApiMatch", dependent: :destroy
  serialize :shop_snapshot, coder: JSON
  scope :registered, -> {
    where("hotpepper_api_targets.state IN ('applied', 'skipped', 'rollback_conflict') OR (hotpepper_api_targets.classification = 'registered' AND hotpepper_api_targets.state != 'rolled_back') OR EXISTS (SELECT 1 FROM hotpepper_api_matches WHERE hotpepper_api_matches.hotpepper_api_target_id = hotpepper_api_targets.id AND hotpepper_api_matches.state IN ('applied', 'skipped', 'rollback_conflict'))")
  }
  scope :held, -> { where(state: "held").where.not(id: registered.select(:id)) }
  scope :excluded, -> { where(state: "excluded").where.not(id: registered.select(:id)) }
  scope :url_conflicts, -> {
    legacy = HotpepperApiMatch.where(state: "conflict", reason: "同じホットペッパーURLが他店舗に登録済みです").select(:hotpepper_api_target_id)
    where(state: "url_conflict").or(where(id: legacy)).where.not(state: [ "excluded", "held" ]).where.not(id: registered.select(:id))
  }
  scope :unregistered, -> { where.not(id: registered.select(:id)).where.not(state: [ "excluded", "held" ]).where.not(id: url_conflicts.select(:id)) }
  CLASSIFICATIONS = { "bulk"=>"一括登録候補", "review"=>"要確認", "unmatched"=>"API検索で候補なし", "registered"=>"登録済み", "conflict"=>"競合" }.freeze
end
