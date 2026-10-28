# frozen_string_literal: true

module SmokingConditionSchedules
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_condition_schedules
    validate :validate_condition_schedules
  end

  def advanced_smoking_schedules?
    smoking_condition_schedules.present?
  end

  def smoking_condition_rows
    rows = [{ key: "primary", area: smoking_area, type: smoking_type }]
    rows << { key: "secondary", area: smoking_area_2, type: smoking_type_2 } if secondary_smoking_condition?
    rows
  end

  def smoking_condition_now?(key)
    return false unless open_now? && !confirmed_non_smoking?

    rule = smoking_condition_schedules.to_h[key.to_s].to_h
    case rule["mode"]
    when "business" then true
    when "unknown" then false
    when "custom" then condition_schedule_matches_now?(rule["hours_text"])
    else legacy_smoking_now?
    end
  end

  def smoking_condition_time_label(key)
    rule = smoking_condition_schedules.to_h[key.to_s].to_h
    case rule["mode"]
    when "business" then "営業時間中"
    when "unknown" then "時間不明・要確認"
    when "custom" then rule["hours_text"].to_s.lines.map(&:strip).join(" / ")
    else smoking_hours_text.presence || (smoking_hours_unset_with_restriction? ? "時間不明・要確認" : "営業時間中")
    end
  end

  def smoking_search_types
    types = [smoking_type]
    if advanced_smoking_schedules?
      types << smoking_type_2
      types << "both_ok" if types.include?("paper_only") && types.include?("electronic_only")
    end
    types.compact.uniq
  end

  def current_smoking_badge_conditions
    rows = smoking_condition_rows.select { |row| smoking_condition_now?(row[:key]) }
    rows.group_by { |row| row[:area] }.map do |area, group|
      types = group.map { |row| row[:type] }
      type = types.include?("both_ok") || (types.include?("paper_only") && types.include?("electronic_only")) ? "both_ok" : types.first
      { area: area, type: type }
    end
  end

  private

  def normalize_condition_schedules
    return unless smoking_condition_schedules.is_a?(Hash)

    self.smoking_condition_schedules = smoking_condition_schedules.stringify_keys.filter_map do |key, value|
      next unless %w[primary secondary].include?(key) && value.is_a?(Hash)
      rule = value.stringify_keys.slice("mode", "hours_text")
      next if rule["mode"].blank?
      rule["hours_text"] = rule["mode"] == "custom" ? rule["hours_text"].to_s.strip : ""
      [key, rule]
    end.to_h
  end

  def validate_condition_schedules
    unless smoking_condition_schedules.is_a?(Hash)
      errors.add(:base, "喫煙の詳細設定が不正です")
      return
    end
    smoking_condition_schedules.each do |key, rule|
      unless %w[business custom unknown].include?(rule["mode"])
        errors.add(:base, "喫煙条件の時間設定を選択してください")
        next
      end
      if key == "secondary" && (smoking_area_2.blank? || smoking_type_2.blank?)
        errors.add(:base, "条件2の場所とタバコの種類を設定してください")
      end
      next unless rule["mode"] == "custom"
      text = rule["hours_text"].to_s
      valid = text.present? && text.length <= 2000 && text.lines.all? do |line|
        value = line.strip
        next true if value.blank?
        body = value.sub(/\A(?:月|火|水|木|金|土|日|祝日|祝前|祝後)\s+/, "")
        next true if %w[喫煙不可 終日禁煙 時間未設定].include?(body)
        pieces = body.split(/[,、]/).map(&:strip)
        pieces.present? && pieces.all? do |piece|
          match = piece.match(/\A(\d{1,2}):(\d{2})\s*[-〜～~－–—]\s*(\d{1,2}):(\d{2})\z/)
          match && match[1].to_i < 24 && match[2].to_i < 60 && match[3].to_i <= 24 && match[4].to_i < 60 &&
            (match[3].to_i != 24 || match[4].to_i.zero?) && [match[1].to_i, match[2].to_i] != [match[3].to_i, match[4].to_i]
        end
      end
      errors.add(:base, "喫煙条件の指定時間は22:00-04:00、または月 22:00-04:00の形式で入力してください") unless valid
    end
  end

  def condition_schedule_matches_now?(text)
    text = text.to_s.tr("～", "〜")
    rows = text.lines.map(&:strip).reject(&:blank?)
    minute = Time.current.hour * 60 + Time.current.min
    unless rows.any? { |line| line.match?(/\A(?:[月火水木金土日]|祝日|祝前|祝後)\s/) }
      return time_ranges_from_text(text).any? { |start, finish| within_range?(minute, start, finish) }
    end
    weekday = weekday_label_for_today
    # An explicit weekday ban also applies on holidays.
    return false if rows.any? { |line| line.match?(/\A#{weekday}\s+(?:喫煙不可|終日禁煙)\z/) }
    label = holiday_today? && rows.any? { |line| line.start_with?("祝日 ") } ? "祝日" : weekday
    today_line = rows.find { |line| line.start_with?("#{label} ") }
    return false if today_line.to_s.match?(/喫煙不可|終日禁煙|時間未設定/)
    today_ranges = time_ranges_from_text(today_line)
    return true if today_ranges.any? { |start, finish| finish > start ? (minute >= start && minute < finish) : minute >= start }
    previous = %w[日 月 火 水 木 金 土][(Time.current.wday - 1) % 7]
    previous_line = rows.find { |line| line.start_with?("#{previous} ") }
    time_ranges_from_text(previous_line).any? { |start, finish| finish <= start && minute < finish }
  end
end
