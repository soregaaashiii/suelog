# frozen_string_literal: true

# Shared token boundaries keep listing queries and SEO counts in agreement.
class ShopGenreFilter
  SEPARATORS = ["　", " ", ",", "，", "/", "／", "｜", "|", "・"].freeze

  def self.tokens(*values)
    values.flat_map do |value|
      normalized = SEPARATORS.reduce(value.to_s) { |text, separator| text.gsub(separator, "、") }
      normalized.split("、").reject(&:blank?)
    end.uniq
  end

  def self.apply(scope, terms)
    return scope if terms.blank?

    expressions = %w[genre genre_other].map do |column|
      SEPARATORS.reduce("COALESCE(shops.#{column}, '')") do |sql, separator|
        "REPLACE(#{sql}, '#{separator}', '、')"
      end
    end
    bindings = {}
    conditions = terms.each_with_index.map do |term, index|
      key = :"genre_token_#{index}"
      bindings[key] = "%、#{ActiveRecord::Base.sanitize_sql_like(term)}、%"
      "(" + expressions.map { |sql| "('、' || #{sql} || '、') LIKE :#{key}" }.join(" OR ") + ")"
    end
    scope.where(conditions.join(" OR "), bindings)
  end
end
