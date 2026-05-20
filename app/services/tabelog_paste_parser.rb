# frozen_string_literal: true

class TabelogPasteParser
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
      budget_range: metadata[:budget_range],
      last_order_text: metadata[:last_order_text],
      private_room_type: metadata[:private_room_type],
      seat_type_tags: metadata[:seat_type_tags],
      all_you_can_drink_type: metadata[:all_you_can_drink_type],
      smoking_area: metadata[:smoking_area],
      smoking_type: metadata[:smoking_type],
      raw_import_text: @raw_text,
      import_metadata: metadata,
      import_source: "tabelog_paste",
      imported_at: Time.current
    }.compact
  end

  private

  def build_metadata
    genre_raw = field_value("ジャンル")
    smoking_raw = field_value("禁煙・喫煙")
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
      nearest_station_raw: extract_nearest_station_raw,
      nearest_station: extract_nearest_station,
      opening_hours_raw: field_value("営業時間"),
      opening_hours_text: extract_opening_hours_text,
      opening_hours_json: extract_opening_hours_json,
      holiday_hours_text: extract_holiday_hours_text,
      closed_days_text: extract_closed_days_text,
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
      "ジャンル",
      "予約・",
      "お問い合わせ",
      "予約・お問い合わせ",
      "予約可否",
      "住所",
      "交通手段",
      "営業時間",
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
    @text.match(/0\d{1,4}[-ー−]?\d{1,4}[-ー−]?\d{3,4}/)&.[](0)&.tr("ー−", "-")
  end

  def extract_address
    raw = field_value("住所")
    return nil if raw.blank?

    raw.lines.map(&:strip).find { |line| line.match?(/大阪府|京都府|兵庫県|奈良県|和歌山県|滋賀県|東京都|北海道|(?:県|府|都)/) }.presence || raw.lines.first.to_s.strip.presence
  end

  def extract_nearest_station_raw
    access = field_value("交通手段").to_s
    station_line = access.lines.map(&:strip).find { |line| line.match?(/駅から\d+m|駅からは|駅きた|駅/) }
    station_line.presence
  end

  def extract_nearest_station
    access = field_value("交通手段").to_s

    distance_line = access.lines.map(&:strip).find { |line| line.match?(/(.+?駅)から\d+m/) }
    return distance_line.match(/(.+?駅)から\d+m/)[1].strip if distance_line.present?

    station_line = access.lines.map(&:strip).find { |line| line.match?(/(.+?駅)/) }
    return station_line.match(/(.+?駅)/)[1].strip if station_line.present?

    nil
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
    raw = field_value("営業時間")
    return nil if raw.blank?

    raw.lines
       .map(&:strip)
       .reject(&:blank?)
       .reject { |line| line.match?(/\AL\.?O\.?\s*\d{1,2}:\d{2}\z/i) }
       .join("\n")
       .presence
  end

  def extract_opening_hours_json
    raw = field_value("営業時間")
    return {} if raw.blank?

    result = {}
    current_days = []

    raw.lines.map(&:strip).reject(&:blank?).each do |line|
      next if line.match?(/\AL\.?O\.?\s*\d{1,2}:\d{2}\z/i)

      if line.match?(/[月火水木金土日祝]/) && !line.match?(/\d{1,2}:\d{2}/)
        current_days = expand_days(line)
        next
      end

      time_match = line.match(/(\d{1,2}:\d{2})\s*[-〜~－–—]\s*(\d{1,2}:\d{2})/)
      next unless time_match
      next if current_days.blank?

      current_days.each do |day_key|
        result[day_key] = {
          "closed" => false,
          "open" => time_match[1],
          "close" => time_match[2],
          "break_enabled" => false,
          "break_start" => "",
          "break_end" => ""
        }
      end
    end

    result
  end

  def expand_days(line)
    days = []

    days << "monday" if line.include?("月")
    days << "tuesday" if line.include?("火")
    days << "wednesday" if line.include?("水")
    days << "thursday" if line.include?("木")
    days << "friday" if line.include?("金")
    days << "saturday" if line.include?("土")
    days << "sunday" if line.include?("日")

    days.uniq
  end

  def extract_holiday_hours_text
    raw = field_value("営業時間")
    return nil if raw.blank?

    current_label = nil
    rows = []

    raw.lines.map(&:strip).reject(&:blank?).each do |line|
      next if line.match?(/\AL\.?O\.?\s*\d{1,2}:\d{2}\z/i)

      if line.match?(/[月火水木金土日祝]/) && !line.match?(/\d{1,2}:\d{2}/)
        current_label = line
        next
      end

      time_match = line.match(/(\d{1,2}:\d{2})\s*[-〜~－–—]\s*(\d{1,2}:\d{2})/)
      next unless time_match

      if current_label.to_s.match?(/祝前日|祝前/)
        rows << "祝前 #{time_match[1]}-#{time_match[2]}"
      end

      if current_label.to_s.match?(/祝日/)
        rows << "祝日 #{time_match[1]}-#{time_match[2]}"
      end
    end

    rows.uniq.join("\n").presence
  end

  def extract_closed_days_text
    raw = field_value("営業時間").to_s
    line = raw.lines.map(&:strip).find { |v| v.match?(/定休日|不定休|無休|休み/) }
    return "不定休" if raw.include?("不定休")
    return "無休" if raw.include?("無休")

    line.to_s.sub(/定休日[:：]?/, "").strip.presence
  end

  def extract_budget_range
    raw = field_value("予算").presence || field_value("予算（口コミ集計）")
    return nil if raw.blank?

    raw.match(/￥?\s*[\d,]+[〜～\-−ー]\s*￥?\s*[\d,]+円?/)&.[](0)&.gsub("￥", "").strip.presence ||
      raw.lines.map(&:strip).find { |line| line.match?(/[\d,]+[〜～\-−ー][\d,]+/) }.presence
  end

  def extract_last_order_text
    matched = @text.scan(/(?:L\.?O\.?|ラストオーダー|LO)[:：\s]*\d{1,2}:\d{2}/i)
    return matched.uniq.join(" / ") if matched.present?

    nil
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
    text = raw.to_s

    return "all_smoking" if text.match?(/全席喫煙|席で喫煙|喫煙可/)
    return "separated" if text.match?(/分煙|喫煙所/)
    return "unknown" if text.match?(/禁煙|不明/)

    nil
  end

  def extract_smoking_type(raw)
    text = raw.to_s

    return "electronic_only" if text.match?(/加熱式/)
    return "both_ok" if text.match?(/全席喫煙|席で喫煙|喫煙可/)
    return "both_ok" if text.match?(/紙.*加熱|加熱.*紙/)
    return "paper_only" if text.match?(/紙タバコ|紙たばこ/)

    "unknown"
  end
end