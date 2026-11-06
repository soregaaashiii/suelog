module AffiliateRegistrationTarget
  extend ActiveSupport::Concern

  included do
    scope :registered, -> {
      table = table_name
      prefix = table.delete_suffix("_targets")
      where("#{table}.state IN ('applied', 'skipped', 'rollback_conflict') OR (#{table}.classification = 'registered' AND #{table}.state != 'rolled_back') OR EXISTS (SELECT 1 FROM #{prefix}_matches WHERE #{prefix}_matches.#{prefix}_target_id = #{table}.id AND #{prefix}_matches.state IN ('applied', 'skipped', 'rollback_conflict'))")
    }
    scope :held, -> { where(state: "held").where.not(id: registered.select(:id)) }
    scope :excluded, -> { where(state: "excluded").where.not(id: registered.select(:id)) }
    scope :url_conflicts, -> {
      table = table_name
      prefix = table.delete_suffix("_targets")
      legacy = klass.reflect_on_association(:matches).klass.where(state: "conflict", reason: "同じ#{klass.registration_provider_label}URLが他店舗に登録済みです").select("#{prefix}_target_id")
      where(state: "url_conflict").or(where(id: legacy)).where.not(state: [ "excluded", "held" ]).where.not(id: registered.select(:id))
    }
    scope :unregistered, -> { where.not(id: registered.select(:id)).where.not(state: [ "excluded", "held" ]).where.not(id: url_conflicts.select(:id)) }
  end
end
