module ShopsHelper
  # Compare only like units: walking times first, otherwise stated distances.
  # This summarizes the supplied access text; it does not geocode the address.
  def compact_station_label(access_text)
    text = access_text.to_s.tr("０１２３４５６７８９", "0123456789")
      .gsub(/[「」『』]/, "").gsub(/\s+駅/, "駅")
    candidates = text.scan(/([^\s、,，・\/／()（）]+駅)\s*(?:(?:より|から)?\s*徒歩\s*(\d+(?:\.\d+)?)\s*分|(?:より|から)\s*(\d+(?:\.\d+)?)\s*(km|m|メートル|キロメートル))?/i).filter_map do |raw_name, minutes, distance, unit|
      name = raw_name.sub(/.*(?:本線|線)/, "").sub(/\A(?:JR|ＪＲ|地下鉄|大阪メトロ|OsakaMetro)/i, "")
      next if name.blank? || name == "駅"

      meters = distance.present? ? distance.to_f * (unit.match?(/km|キロ/i) ? 1000 : 1) : nil
      { name: name, minutes: minutes.presence&.to_f, meters: meters }
    end
    return access_text.to_s.presence if candidates.empty?

    timed = candidates.select { |candidate| candidate[:minutes] }
    measured = candidates.select { |candidate| candidate[:meters] }
    chosen = timed.min_by { |candidate| candidate[:minutes] } || measured.min_by { |candidate| candidate[:meters] } || candidates.first
    if chosen[:minutes]
      "#{chosen[:name]} 徒歩#{format('%g', chosen[:minutes])}分"
    elsif chosen[:meters]
      "#{chosen[:name]}から#{format('%g', chosen[:meters])}m"
    else
      chosen[:name]
    end
  end

  def closing_soon_label(shop)
    return nil unless shop.respond_to?(:open_now?) && shop.open_now?

    closing_time = shop.today_closing_time rescue nil
    return nil if closing_time.blank?

    minutes_left = ((closing_time - Time.current) / 60).to_i
    return nil if minutes_left <= 0

    if minutes_left <= 120
      "あと#{minutes_left}分で閉店"
    else
      nil
    end
  end
end