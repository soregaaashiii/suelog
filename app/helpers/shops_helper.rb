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
end