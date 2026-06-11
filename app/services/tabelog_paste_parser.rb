# frozen_string_literal: true

class TabelogPasteParser
  TIME_RANGE_PATTERN = /(\d{1,2}:\d{2})\s*[-〜～~－–—]\s*(\d{1,2}:\d{2})/

  def self.call(raw_text)
    new(raw_text).call
  end

  def initialize(raw_text)
    @raw_text = raw_text.to_s
    @text = normalize_text(@raw_text)
  end

  def call
    metadata = build_metadata

    {
      name: metadata[:name],
      phone: metadata[:phone],
      address: metadata[:address],
      nearest_station: metadata[:nearest_station],
      genre: metadata[:genre],
      genre_other: metadata[:genre_other],
      opening_hours_text: metadata[:opening_hours_text],
      opening_hours_json: metadata[:opening_hours_json],
      holiday_hours_text: metadata[:holiday_hours_text],
      closed_days_text: metadata[:closed_days_text],
      special_hours_note: metadata[:special_hours_note],
      budget_range: metadata[:budget_range],
      last_order_text: metadata[:last_order_text],
      private_room_type: metadata[:private_room_type],
      seat_type_tags: metadata[:seat_type_tags],
      all_you_can_drink_type: metadata[:all_you_can_drink_type],
      smoking_area: metadata[:smoking_area],
      smoking_type: metadata[:smoking_type],
      smoking_hours_text: metadata[:smoking_hours_text],
      public_store_details: metadata[:smoking_note],
      raw_import_text: @raw_text,
      import_metadata: metadata,
      import_source: "tabelog_paste",
      imported_at: Time.current
    }.compact
  end

  private

  def build_metadata
    genre_raw = field_value("ジャンル")
    smoking_raw = field_value_with_continuation("禁煙・喫煙")
    private_room_raw = field_value("個室")
    space_raw = field_value("空間・設備")
    drink_raw = field_value("ドリンク")
    course_raw = field_value("コース")
    menu_raw = section_text("メニュー")

    {
      name: extract_name,
      genre_raw: genre_raw,
      genre: normalize_genre(genre_raw),
      genre_other: genre_other(genre_raw),
      phone: extract_phone,
      address: extract_address,
      access_raw: field_value("交通手段"),
      nearest_station_raw: field_value("交通手段"),
      nearest_station: extract_nearest_station_text,
      opening_hours_raw: opening_hours_field_value,
      opening_hours_text: extract_opening_hours_text,
      opening_hours_json: extract_opening_hours_json,
      holiday_hours_text: extract_holiday_hours_text,
      closed_days_text: extract_closed_days_text,
      special_hours_note: extract_special_hours_note,
      budget_raw: field_value("予算"),
      budget_review_raw: field_value("予算（口コミ集計）"),
      budget_range: extract_budget_range,
      last_order_text: extract_last_order_text,
      private_room_raw: private_room_raw,
      private_room_type: extract_private_room_type(private_room_raw),
      seat_count_raw: field_value("席数"),
      seat_type_tags: extract_seat_type_tags(space_raw),
      all_you_can_drink_type: extract_all_you_can_drink_type(course_raw, menu_raw),
      smoking_raw: smoking_raw,
      smoking_area: extract_smoking_area(smoking_raw),
      smoking_type: extract_smoking_type(smoking_raw),
      smoking_hours_text: extract_smoking_hours_text,
      smoking_note: extract_smoking_note,
      charter_raw: field_value("貸切"),
      parking_raw: field_value("駐車場"),
      payment_raw: field_value("支払い方法"),
      space_raw: space_raw,
      drink_raw: drink_raw
    }
  end

  def normalize_text(text)
    text.to_s
        .gsub("\r\n", "\n")
        .gsub("\r", "\n")
        .gsub(/\u00A0/, " ")
        .lines
        .map(&:rstrip)
        .join("\n")
  end

  def lines
    @lines ||= @text.lines.map(&:strip)
  end

  def compact_lines
    @compact_lines ||= lines.reject(&:blank?)
  end

  def field_value(label)
    idx = compact_lines.index { |line| line == label || line.start_with?("#{label}\t") }
    return nil if idx.nil?

    current = compact_lines[idx]

    if current.include?("\t")
      value = current.split("\t", 2).last.to_s.strip
      return value.presence
    end

    values = []
    compact_lines[(idx + 1)..].to_a.each do |line|
      break if known_label?(line)

      values << line
    end

    values.join("\n").strip.presence
  end

  def field_value_with_continuation(label)
    idx = compact_lines.index { |line| line == label || line.start_with?("#{label}\t") }
    return nil if idx.nil?

    values = []
    current = compact_lines[idx]

    if current.include?("\t")
      values << current.split("\t", 2).last.to_s.strip
    end

    compact_lines[(idx + 1)..].to_a.each do |line|
      break if known_label?(line)

      values << line
    end

    values.reject(&:blank?).join("\n").strip.presence
  end

  def opening_hours_field_value
    raw = field_value("営業時間").to_s
    return nil if raw.blank?

    lines = raw.lines.map(&:strip).reject(&:blank?)
    kept = []

    lines.each do |line|
      break if line.match?(/\A予算\z|予算（口コミ集計）|支払い方法|席・設備|禁煙・喫煙|求人情報|ホールスタッフ|調理師|料理長候補/)
      break if line.match?(/\A勤務時間/)
      break if line.match?(/\A■\s*営業時間/)
      break if line.match?(/\A【月/)

      kept << line
    end

    kept.join("\n").presence
  end

  def section_text(label)
    idx = compact_lines.index { |line| line == label }
    return nil if idx.nil?

    values = []
    compact_lines[(idx + 1)..].to_a.each do |line|
      break if main_section_label?(line)

      values << line
    end

    values.join("\n").strip.presence
  end

  def known_label?(line)
    normalized = line.to_s.strip
    known_labels.any? { |label| normalized == label || normalized.start_with?("#{label}\t") }
  end

  def main_section_label?(line)
    %w[席・設備 メニュー 特徴・関連情報].include?(line.to_s.strip)
  end

  def known_labels
    @known_labels ||= [
      "店名",
      "受賞・選出歴",
      "ジャンル",
      "予約・",
      "お問い合わせ",
      "予約・お問い合わせ",
      "予約可否",
      "住所",
      "交通手段",
      "営業時間",
      "■ 定休日",
      "■ 年末年始",
      "■ご予約に関しまして",
      "■ ご予約に関しまして",
      "予算",
      "予算（口コミ集計）",
      "支払い方法",
      "席数",
      "最大予約可能人数",
      "個室",
      "貸切",
      "禁煙・喫煙",
      "駐車場",
      "空間・設備",
      "コース",
      "ドリンク",
      "料理",
      "ロケーション"
    ]
  end

  def extract_name
    field_value("店名") || compact_lines.first
  end

  def extract_phone
    raw = field_value("電話番号").presence ||
          field_value("予約・お問い合わせ").presence ||
          field_value("お問い合わせ").presence

    return nil if raw.blank?
    return nil if raw.match?(/非公開|未公開|不明/)

    raw.match(/0\d{1,4}[-ー−]?\d{1,4}[-ー−]?\d{3,4}/)&.[](0)&.tr("ー−", "-")
  end

  def extract_address
    raw = field_value("住所")
    return nil if raw.blank?

    raw.lines.map(&:strip).find { |line| line.match?(/大阪府|京都府|兵庫県|奈良県|和歌山県|滋賀県|東京都|北海道|(?:県|府|都)/) }.presence || raw.lines.first.to_s.strip.presence
  end

  def extract_nearest_station_raw
    field_value("交通手段")
  end

  def extract_nearest_station_text
    field_value("交通手段").to_s.strip.presence
  end

  def normalize_genre(raw)
    first = raw.to_s.split(/[、,\/]/).map(&:strip).reject(&:blank?).find do |genre|
      Shop.genre_options.include?(genre)
    end

    first.presence || "その他"
  end

  def genre_other(raw)
    values = raw.to_s.split(/[、,\/]/).map(&:strip).reject(&:blank?)
    values.reject { |genre| genre == normalize_genre(raw) }.join("、").presence
  end

  def extract_opening_hours_text
    raw = opening_hours_field_value
    return nil if raw.blank?

    smoking_hours_by_day = extract_smoking_hours_by_day
    rows_by_day = {}
    current_day_keys = []
    current_hours = []

    flush_hours = lambda do
      if current_day_keys.present? && current_hours.present?
        current_day_keys.each do |day_key|
          display_hours = apply_smoking_suffix_to_hours(day_key, current_hours, smoking_hours_by_day)
          label = day_label(day_key)
          existing_hours = rows_by_day[day_key].to_s.sub(/\A#{Regexp.escape(label)}\s*/, "").split(/\s*,\s*/).reject(&:blank?)
          merged_hours = (existing_hours + display_hours).uniq.sort_by { |hours| hours[/\d{1,2}:\d{2}/].to_s }
          rows_by_day[day_key] = "#{label} #{merged_hours.join(', ')}"
        end
      end

      current_hours = []
    end

    raw.lines.map(&:strip).reject(&:blank?).each do |line|
      lo_text =
        if line.match?(/\A[（(]?\s*L\.?O\.?/i)
          line.sub(/\A[（(]?\s*L\.?O\.?\s*/i, "").sub(/[）)]\z/, "").strip
        end

      if lo_text.present? && current_hours.last.present?
        current_hours[-1] = "#{current_hours.last.sub(/（L\.O\. [^)]+）/, "")}（L.O. #{lo_text}）"
        next
      end

      if day_label_line?(line)
        flush_hours.call
        current_day_keys = expand_days(line)
        next
      end

      cleaned = line.sub(/\A■\s*/, "").strip

      if cleaned.match?(/\A定休日[:：]?\z/)
        if current_hours.present?
          flush_hours.call
        elsif current_day_keys.present?
          current_day_keys.each do |day_key|
            rows_by_day[day_key] = "#{day_label(day_key)} 定休日"
          end
        end

        current_day_keys = []
        current_hours = []
        next
      end

      next if cleaned.match?(/年中無休|無休/)

      time_match = line.match(TIME_RANGE_PATTERN)
      if time_match
        current_day_keys = standard_day_keys if current_day_keys.blank?
        current_hours << "#{time_match[1]}-#{time_match[2]}"
      end
    end

    flush_hours.call

    ordered_day_keys.filter_map { |day_key| rows_by_day[day_key] }
                    .reject { |row| row.to_s.include?("定休日") }
                    .join("\n")
                    .presence
  end

  def extract_opening_hours_json
    raw = opening_hours_field_value
    return {} if raw.blank?

    periods_by_day = {}
    current_days = []

    raw.lines.map(&:strip).reject(&:blank?).each do |line|
      next if line.match?(/\A[（(]?\s*L\.?O\.?\s*\d{1,2}:\d{2}[）)]?\z/i)

      if day_label_line?(line)
        current_days = expand_days(line)
        next
      end

      cleaned = line.sub(/\A■\s*/, "").strip

      if cleaned.match?(/\A定休日[:：]?\z/)
        if current_days.present? && current_days.none? { |day_key| periods_by_day[day_key].present? }
          current_days.each do |day_key|
            periods_by_day[day_key] = []
          end
        end

        current_days = []
        next
      end

      next if cleaned.match?(/年中無休|無休/)
      next if line.match?(/\d{1,2}月\d{1,2}日|\d{4}年\d{1,2}月\d{1,2}日/)

      time_match = line.match(TIME_RANGE_PATTERN)
      next unless time_match

      current_days = standard_day_keys if current_days.blank?

      current_days.each do |day_key|
        periods_by_day[day_key] ||= []
        periods_by_day[day_key] << [time_match[1], time_match[2]]
      end
    end

    periods_by_day.each_with_object({}) do |(day_key, periods), result|
      periods = periods.uniq

      if periods.blank?
        result[day_key] = {
          "closed" => true,
          "open" => "",
          "close" => "",
          "break_enabled" => false,
          "break_start" => "",
          "break_end" => ""
        }
      elsif periods.size >= 2
        first_open, first_close = periods[0]
        second_open, second_close = periods[1]

        result[day_key] = {
          "closed" => false,
          "open" => first_open,
          "close" => second_close,
          "break_enabled" => true,
          "break_start" => first_close,
          "break_end" => second_open
        }
      else
        open_time, close_time = periods[0]

        result[day_key] = {
          "closed" => false,
          "open" => open_time,
          "close" => close_time,
          "break_enabled" => false,
          "break_start" => "",
          "break_end" => ""
        }
      end
    end
  end

  def expand_days(line)
    text = line.to_s
    normalized = text.gsub("祝前日", "祝前").gsub("祝後日", "祝後")
    day_tokens = normalized.split(/[・、\/\s]+/).reject(&:blank?)
    days = []

    day_order = {
      "月" => "monday",
      "火" => "tuesday",
      "水" => "wednesday",
      "木" => "thursday",
      "金" => "friday",
      "土" => "saturday",
      "日" => "sunday"
    }

    normalized.scan(/([月火水木金土日])[～〜\-−ー]([月火水木金土日])/).each do |start_day, end_day|
      keys = day_order.keys
      start_index = keys.index(start_day)
      end_index = keys.index(end_day)
      next if start_index.nil? || end_index.nil?

      keys[start_index..end_index].each do |day|
        days << day_order[day]
      end
    end

    days << "monday" if day_tokens.include?("月")
    days << "tuesday" if day_tokens.include?("火")
    days << "wednesday" if day_tokens.include?("水")
    days << "thursday" if day_tokens.include?("木")
    days << "friday" if day_tokens.include?("金")
    days << "saturday" if day_tokens.include?("土")
    days << "sunday" if day_tokens.include?("日")
    days << "holiday" if day_tokens.include?("祝日") || day_tokens.include?("祝") || day_tokens.include?("祝後")
    days << "pre_holiday" if day_tokens.include?("祝前")

    days.uniq
  end

  def extract_holiday_hours_text
    nil
  end

  def day_label_line?(line)
    text = line.to_s.strip
    return false if text.blank?
    return false if text.match?(/\d{1,2}:\d{2}/)
    return false if text.start_with?("■")
    return false if text.match?(/営業時間|定休日|休業|年末年始|変更|通常営業|ランチ|ディナー|最終入店/)

    text.match?(/\A[月火水木金土日祝前後・、\/\s～〜\-−ー]+(?:曜日|曜)?\z/) ||
      text.match?(/\A(?:祝日|祝前日|祝後日|土日祝|平日)\z/)
  end

  def standard_day_keys
    %w[monday tuesday wednesday thursday friday saturday sunday holiday pre_holiday]
  end

  def extract_smoking_hours_by_day
    smoking_raw = field_value_with_continuation("禁煙・喫煙").to_s
    opening_raw = opening_hours_field_value.to_s
    return {} if smoking_raw.blank?

    result = {}

    until_hour_match = smoking_raw.match(/(\d{1,2})時まで.*(?:加熱式たばこ限定|加熱式タバコ限定|加熱式限定|喫煙可)/)

    if until_hour_match
      smoking_end = format_hour_text(until_hour_match[1])

      opening_ranges_by_day.each do |day_key, ranges|
        first_open = ranges.first&.first
        next if first_open.blank?

        result[day_key] = "#{first_open}-#{smoking_end}"
      end

      return result if result.present?
    end

    smoking_raw.lines.map(&:strip).reject(&:blank?).each do |line|
      next unless line.include?("喫煙")
      next if line.match?(/営業時間中|終日/)

      time_match = line.match(TIME_RANGE_PATTERN)
      next unless time_match

      range = "#{time_match[1]}-#{time_match[2]}"
      days = expand_days(line)
      days = standard_day_keys if days.blank?

      days.each do |day|
        result[day] = range
      end
    end

    if result.blank? &&
       smoking_raw.match?(/ランチタイム.*禁煙|ランチ.*禁煙|ランチタイムのみ禁煙|ディナーのみ喫煙可/) &&
       smoking_raw.match?(/分煙|喫煙可|加熱式|全席喫煙/)
      opening_ranges_by_day.each do |day_key, ranges|
        dinner_range = latest_daily_time_range(ranges)
        result[day_key] = dinner_range if dinner_range.present?
      end
    end

    result
  end

  def format_hour_text(hour)
    format("%02d:00", hour.to_i)
  end

  def opening_ranges_by_day
    raw = opening_hours_field_value.to_s
    result = {}
    current_days = []

    raw.lines.map(&:strip).reject(&:blank?).each do |line|
      if day_label_line?(line)
        current_days = expand_days(line)
        next
      end

      cleaned = line.sub(/\A■\s*/, "").strip
      next if cleaned.match?(/\A定休日[:：]?\z/)
      next if cleaned.match?(/年中無休|無休/)
      next if line.match?(/\d{1,2}月\d{1,2}日|\d{4}年\d{1,2}月\d{1,2}日/)

      time_match = line.match(TIME_RANGE_PATTERN)
      next unless time_match

      current_days = standard_day_keys if current_days.blank?

      current_days.each do |day_key|
        result[day_key] ||= []
        result[day_key] << [time_match[1], time_match[2]]
      end
    end

    result
  end

  def time_to_minutes(time_text)
    hour, minute = time_text.to_s.split(":").map(&:to_i)
    (hour * 60) + minute
  end

  def latest_daily_time_range(ranges)
    ranges.to_a
          .uniq
          .max_by do |open_text, close_text|
            open_minutes = time_to_minutes(open_text)
            close_minutes = time_to_minutes(close_text)
            close_minutes += 24 * 60 if close_minutes <= open_minutes
            close_minutes
          end
          &.then { |open_text, close_text| "#{open_text}-#{close_text}" }
  end

  def dinner_range_from_opening_hours(raw)
    ranges = raw.to_s.scan(TIME_RANGE_PATTERN).map do |open_text, close_text|
      "#{open_text}-#{close_text}"
    end

    ranges.uniq[1]
  end

  def ordered_day_keys
    %w[monday tuesday wednesday thursday friday saturday sunday holiday pre_holiday]
  end

  def day_label(day_key)
    {
      "monday" => "月",
      "tuesday" => "火",
      "wednesday" => "水",
      "thursday" => "木",
      "friday" => "金",
      "saturday" => "土",
      "sunday" => "日",
      "holiday" => "祝日",
      "pre_holiday" => "祝前"
    }[day_key]
  end

  def apply_smoking_suffix_to_hours(day_key, current_hours, smoking_hours_by_day)
    return current_hours if smoking_hours_by_day.blank?

    smoking_range = smoking_hours_by_day[day_key]
    return current_hours if smoking_range.blank?

    current_hours.map do |hours|
      next hours if hours.include?("（喫煙可：")
      next hours unless hours.start_with?(smoking_range)

      "#{hours}（喫煙可：#{smoking_range}）"
    end
  end

  def extract_closed_days_text
    lines = @text.lines.map(&:strip).reject(&:blank?)

    lines.each_with_index do |line, index|
      cleaned = line.sub(/\A■\s*/, "").strip

      if cleaned.match?(/\A定休日[:：]?\z/)
        return lines[(index + 1)..].to_a.find { |v| v.present? && !v.start_with?("■") }.to_s.strip.presence
      end

      if cleaned.match?(/\A定休日[:：]/)
        return cleaned.sub(/\A定休日[:：]?/, "").strip.presence
      end
    end

    raw = opening_hours_field_value.to_s
    return "不定休" if raw.include?("不定休")
    return "無休" if raw.include?("無休") || raw.include?("年中無休")

    nil
  end

  def extract_special_hours_note
    raw = field_value("営業時間").to_s
    return nil if raw.blank?

    notes = []

    raw.lines.map(&:strip).reject(&:blank?).each do |line|
      cleaned = line.sub(/\A■\s*/, "").strip

      next if cleaned.blank?
      next if day_label_line?(cleaned)
      next if cleaned.match?(/\A\d{1,2}:\d{2}\s*[-〜～~－–—]\s*\d{1,2}:\d{2}\z/)
      next if cleaned.match?(/\A[（(]?\s*L\.?O\.?\s*(?:料理|ドリンク|フード)?\s*\d{1,2}:\d{2}[）)]?\z/i)
      next if cleaned.match?(/\A定休日\z/)

      if cleaned.match?(/定休日|不定休|無休|年末年始|臨時休業|休業|営業時間変更|通常営業|準ずる|日曜、祝日やってます/)
        notes << cleaned
      end
    end

    notes.uniq.join("\n").strip.presence
  end

  def extract_budget_range
    raw = field_value("予算").presence || field_value("予算（口コミ集計）")
    return nil if raw.blank?

    matched_range = raw.match(/￥?\s*[\d,]+[〜～\-−ー]\s*￥?\s*[\d,]+円?/)&.[](0)

    matched_range.to_s.gsub("￥", "").strip.presence ||
      raw.lines.map(&:strip).find { |line| line.match?(/[\d,]+[〜～\-−ー][\d,]+/) }.presence ||
      raw.lines.map(&:strip).find { |line| line.match?(/～?￥?\s*[\d,]+/) }&.gsub("￥", "")&.strip.presence
  end

  def extract_last_order_text
    raw = opening_hours_field_value.to_s
    return nil if raw.blank?

    last_orders = raw.lines.map(&:strip).filter_map do |line|
      normalized = line.tr("：", ":")

      if normalized.match?(/\A[（(]?\s*L\.?O\.?\s*(.+?)[）)]?\z/i)
        normalized.sub(/\A[（(]?\s*L\.?O\.?\s*/i, "").sub(/[）)]\z/, "").strip
      elsif normalized.match?(/L\.?O\.?\s*(料理|ドリンク)?\s*(\d{1,2}:\d{2})/i)
        label = Regexp.last_match(1).to_s
        time = Regexp.last_match(2).to_s
        label.present? ? "#{label}#{time}" : time
      end
    end

    last_orders.reject(&:blank?).uniq.join(" / ").presence
  end

  def extract_private_room_type(raw)
    text = raw.to_s

    return "semi_private_room" if text.match?(/半個室/)
    return "full_private_room" if text.match?(/完全個室|個室\s*有|有/)
    return "no_private_room" if text.match?(/無|なし|無し/)

    "unknown"
  end

  def extract_seat_type_tags(space_raw)
    text = [space_raw, @text].compact.join("\n")
    tags = []

    tags << "counter" if text.match?(/カウンター/)
    tags << "table" if text.match?(/テーブル/)
    tags << "sofa" if text.match?(/ソファ/)
    tags << "standing" if text.match?(/立ち飲み|立飲み/)
    tags << "horigotatsu" if text.match?(/掘りごたつ|掘ごたつ/)
    tags << "terrace" if text.match?(/テラス/)

    tags.uniq
  end

  def extract_all_you_can_drink_type(course_raw, menu_raw)
    text = [course_raw, menu_raw, @text].compact.join("\n")

    return "has_all_you_can_drink" if text.match?(/飲み放題/)
    return "no_all_you_can_drink" if text.match?(/飲み放題\s*(?:無|なし|無し)/)

    "unknown"
  end

  def extract_smoking_area(raw)
    text = [raw, @text].compact.join("\n")

    return "all_smoking" if text.match?(/テラス席.*喫煙可|喫煙可.*テラス席/)
    return "separated" if text.match?(/入口横.*喫煙可|店外.*喫煙可|屋外.*喫煙可|ベンチ.*喫煙|喫煙.*ベンチ|喫煙所|喫煙スペース|喫煙ブース|喫煙専用室/)
    return "unknown" if text.match?(/分煙/)
    return "all_smoking" if text.match?(/全席喫煙|席で喫煙|喫煙可/)
    return "unknown" if text.match?(/全席禁煙|禁煙|不明/)

    nil
  end

  def extract_smoking_type(raw)
    text = [raw, @text].compact.join("\n")

    return "electronic_only" if text.match?(/電子タバコのみ|電子たばこのみ|加熱式たばこのみ|加熱式タバコのみ|加熱式のみ/)
    return "electronic_only" if text.match?(/加熱式たばこ限定|加熱式タバコ限定|加熱式限定/)
    return "both_ok" if text.match?(/紙.*加熱|加熱.*紙/)
    return "paper_only" if text.match?(/紙タバコのみ|紙たばこのみ|紙巻きのみ|紙巻たばこのみ/)
    return "unknown" if text.match?(/入口横.*喫煙可|店外.*喫煙可|屋外.*喫煙可|ベンチ.*喫煙|喫煙.*ベンチ|喫煙所|喫煙スペース|喫煙ブース|分煙/)
    return "both_ok" if text.match?(/全席喫煙|席で喫煙|喫煙可/)
    return "both_ok" if text.match?(/紙タバコ|紙たばこ/)

    "unknown"
  end

  def extract_smoking_hours_text
    smoking_raw = field_value_with_continuation("禁煙・喫煙").to_s
    opening_text = extract_opening_hours_text.to_s
    opening_raw = opening_hours_field_value.to_s
    scoped_text = [smoking_raw, opening_raw].join("\n")

    weekday_lunch_non_smoking_match =
      scoped_text.match(/平日ランチタイム（?月[～〜\-−ー]金）?\s*(\d{1,2}:\d{2})[～〜\-−ー](\d{1,2}:\d{2}).*全席禁煙/)

    if weekday_lunch_non_smoking_match
      smoking_start = weekday_lunch_non_smoking_match[2]

      rows = opening_text.lines.map(&:strip).filter_map do |line|
        day = line[/\A(\S+)\s+/, 1]
        ranges = line.scan(/(\d{1,2}:\d{2})-(\d{1,2}:\d{2})/)

        next if day.blank? || ranges.blank?

        open_time, close_time = ranges.last

        if %w[月 火 水 木 金].include?(day)
          "#{day} #{smoking_start} - #{close_time}"
        else
          "#{day} #{open_time} - #{close_time}"
        end
      end

      return rows.join("\n").presence if rows.present?
    end

    if scoped_text.match?(/ランチタイム.*禁煙|ランチ.*禁煙|ランチは禁煙|ディナーのみ喫煙可/) &&
       scoped_text.match?(/ディナー.*分煙|ディナー.*喫煙|分煙|喫煙可/)
      rows = opening_text.lines.map(&:strip).filter_map do |line|
        day = line[/\A(\S+)\s+/, 1]
        ranges = line.scan(/(\d{1,2}:\d{2})-(\d{1,2}:\d{2})/)

        next if day.blank? || ranges.size < 2

        dinner_open, dinner_close = ranges[1]
        "#{day} #{dinner_open} - #{dinner_close}"
      end

      return rows.join("\n").presence if rows.present?
    end

    until_hour_match = scoped_text.match(/(\d{1,2})時まで.*(?:加熱式たばこ限定|加熱式タバコ限定|加熱式限定|喫煙可)/)

    return "#{until_hour_match[1]}:00まで" if until_hour_match

    start_time =
      scoped_text[/(\d{1,2}[:：]\d{2})\s*までは全席禁煙/, 1] ||
      scoped_text[/(\d{1,2}[:：]\d{2})\s*[〜～~\-－–—]?\s*喫煙可/, 1]

    return nil if start_time.blank?

    start_time = start_time.tr("：", ":")
    end_time = latest_closing_time_from_opening_hours(opening_raw)

    return start_time if end_time.blank?

    "#{start_time} - #{end_time}"
  end

  def opening_time_ranges(raw)
    raw.to_s.scan(TIME_RANGE_PATTERN)
  end

  def latest_closing_time_from_opening_hours(raw)
    times = raw.to_s.scan(TIME_RANGE_PATTERN).map do |_open_time, close_time|
      close_time
    end

    times.last
  end

  def extract_smoking_note
    smoking_raw = field_value_with_continuation("禁煙・喫煙").to_s
    text = @text.to_s

    notes = []

    smoking_raw.lines.map(&:strip).reject(&:blank?).each do |line|
      next if line.match?(/2020年4月1日|受動喫煙対策|改正健康増進法|最新の情報|ご来店前|店舗にご確認/)
      next if line.match?(/\A\d{1,2}[:：]\d{2}\s*[〜～~\-－–—]?\s*喫煙可\z/)

      notes << line if line.match?(/分煙|喫煙できるスペース|喫煙スペース|喫煙ブース|喫煙所|喫煙専用室|喫煙可|禁煙/)
    end

    if text.match?(/テラス席.*喫煙可|喫煙可.*テラス席/)
      notes << "テラス席は喫煙可"
    end

    if text.match?(/入口横.*喫煙可|ベンチ.*喫煙/)
      notes << "店外ベンチで喫煙可"
    end

    if text.match?(/店内.*喫煙スペース|喫煙スペース.*店内/)
      notes << "店内に喫煙スペースあり"
    end

    notes.uniq.join("\n").presence
  end
end