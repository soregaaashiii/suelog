module AffiliateRegistration
  module Ordering
    def self.call(prefix, group)
      raise ArgumentError, "対応していない登録先です" unless %w[gurunavi_csv hotpepper_api].include?(prefix)
      targets, matches = "#{prefix}_targets", "#{prefix}_matches"
      case group
      when "excluded"
        "COALESCE(#{targets}.excluded_at, #{targets}.updated_at) DESC, #{targets}.id DESC"
      when "registered"
        "COALESCE((SELECT MAX(recent.applied_at) FROM #{matches} recent WHERE recent.#{prefix}_target_id = #{targets}.id AND recent.state IN ('applied', 'rollback_conflict')), #{targets}.created_at) DESC, #{targets}.id DESC"
      else
        "CASE WHEN EXISTS (SELECT 1 FROM #{matches} WHERE #{matches}.#{prefix}_target_id = #{targets}.id) THEN 0 ELSE 1 END ASC, #{targets}.confidence DESC, COALESCE(csv_access.views_count, 0) DESC, #{targets}.shop_id ASC"
      end
    end
  end
end
