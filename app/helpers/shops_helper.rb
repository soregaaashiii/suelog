module ShopsHelper
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

  def shop_smoking_status_badges(shop)
    return smoking_unknown_badges(shop) if shop.respond_to?(:smoking_unverified?) && shop.smoking_unverified?
    return smoking_unknown_badges(shop) if shop.smoking_area.to_s == "unknown"

    badges = []

    if shop.smoking_area.to_s == "all_smoking"
      badges << { label: "喫煙可", class_name: "ss-badge ss-badge--dark" }

      case shop.smoking_type.to_s
      when "both_ok", "paper_only"
        badges << { label: "紙タバコOK", class_name: "ss-badge ss-badge--gold" }
      when "electronic_only"
        badges << { label: "加熱式たばこOK", class_name: "ss-badge ss-badge--gold" }
      end
    elsif shop.smoking_area.to_s == "separated"
      badges << { label: "喫煙所あり", class_name: "ss-badge ss-badge--line" }
    end

    if shop.last_confirmed_on.present?
      badges << {
        label: "#{shop.last_confirmed_on.strftime('%Y年%-m月')}確認済み",
        class_name: "ss-badge ss-badge--green"
      }
    end

    badges.presence || smoking_unknown_badges(shop)
  end

  def shop_smoking_status_note(shop)
    if shop.respond_to?(:smoking_unverified?) && shop.smoking_unverified?
      "最新情報は店舗へご確認ください"
    elsif shop.smoking_area.to_s == "unknown"
      "最新情報は店舗へご確認ください"
    else
      nil
    end
  end

  private

  def smoking_unknown_badges(_shop)
    [
      { label: "喫煙情報確認中", class_name: "ss-badge ss-badge--warn" }
    ]
  end
end