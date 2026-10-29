module RefineDesignHelper
  def refine_business_status_badge(open_now)
    state, icon, label = open_now ? [ "open", "●", "営業中" ] : [ "outside", "◷", "営業時間外" ]
    tag.span(class: "refine-business-status refine-business-status--#{state}") do
      safe_join([ tag.span(icon, aria: { hidden: true }), tag.span(label) ])
    end
  end

  def refine_verification_badge(shop)
    return if shop.confirmed_non_smoking?

    state, icon, label = shop.smoking_unverified? ? [ "unverified", "?", "喫煙情報 未確認" ] : [ "verified", "✓", "喫煙情報 確認済み" ]
    tag.span(class: "refine-verification refine-verification--#{state}") do
      safe_join([ tag.span(icon, aria: { hidden: true }), tag.span(label) ])
    end
  end

  def refine_shop_smoking_badges(shop)
    unless shop.confirmed_non_smoking?
      return refine_advanced_smoking_badges(shop) if shop.advanced_smoking_schedules?
      badges = refine_smoking_badges(shop.smoking_area, shop.smoking_type)
      if shop.smoking_seat_locations?
        places = shop.smoking_condition_rows.filter_map { |row| shop.smoking_seat_location_label(row[:key]) }.uniq
        return safe_join([badges, tag.span(places.join(" ／ "), class: "smoking-seat-location", style: "display:block; width:100%; font-size:12px;")], " ")
      end
      return badges
    end

    tag.span(class: "smoking-badge smoking-badge--non-smoking") do
      safe_join([ tag.span(refine_smoking_icon(:non_smoking), class: "smoking-badge-icons", aria: { hidden: true }), tag.span("禁煙店") ])
    end
  end

  def refine_advanced_smoking_badges(shop)
    conditions = shop.open_now? ? shop.current_smoking_badge_conditions : shop.smoking_condition_rows
    badges = conditions.map { |row| refine_smoking_badges(row[:area], row[:type]) }
    if badges.empty?
      label = if shop.smoking_condition_rows.any? { |row| shop.smoking_situation_note(row[:key]).present? }
        "状況により禁煙・要確認"
      elsif shop.smoking_condition_schedules.values.any? { |rule| rule["mode"] == "unknown" }
        "喫煙時間は要確認"
      else
        "現在は喫煙不可"
      end
      badges << tag.span(label, class: "smoking-badge smoking-badge--unknown")
    end
    labels = { "electronic_only" => "加熱式", "paper_only" => "紙", "both_ok" => "紙・加熱式", "unknown" => "種類不明" }
    notes = shop.smoking_condition_rows.map do |row|
      place = row[:area] == "separated" ? "喫煙所" : (shop.smoking_seat_location_label(row[:key]) || "席")
      description = "#{place}・#{labels[row[:type]] || '種類不明'}：#{shop.smoking_condition_time_label(row[:key])}"
      if (note = shop.smoking_situation_note(row[:key]))
        description += "（状況により禁煙・要確認：#{note}）"
      end
      description
    end
    badges << tag.span(notes.join(" ／ "), class: "smoking-schedule-note", style: "display:block; width:100%; font-size:12px; line-height:1.7; color:inherit; margin-top:4px;")
    safe_join(badges, " ")
  end

  def refine_smoking_badges(area, type)
    safe_join([ refine_smoking_badge(:area, area), refine_smoking_badge(:type, type) ], " ")
  end

  def refine_smoking_badge(kind, value)
    state, label, icons = if kind == :area
      { "all_smoking" => [ "seat", "\u5E2D\u3067\u55AB\u7159\u53EF", [ :seat ] ],
        "separated" => [ "room", "\u55AB\u7159\u6240\u3042\u308A", [ :room ] ] }.fetch(value.to_s, [ "unknown", "\u55AB\u7159\u5834\u6240\u4E0D\u660E", [ :unknown ] ])
    else
      { "both_ok" => [ "both", "\u7D19\u30FB\u52A0\u71B1\u5F0FOK", [ :paper, :heated ] ],
        "electronic_only" => [ "heated", "\u52A0\u71B1\u5F0F\u306E\u307F", [ :heated ] ],
        "paper_only" => [ "paper", "\u7D19\u306E\u307F", [ :paper ] ] }.fetch(value.to_s, [ "unknown", "\u305F\u3070\u3053\u7A2E\u985E\u4E0D\u660E", [ :unknown ] ])
    end
    tag.span(class: "smoking-badge smoking-badge--#{state}") do
      safe_join([ tag.span(safe_join(icons.map { |icon| refine_smoking_icon(icon) }), class: "smoking-badge-icons", aria: { hidden: true }), tag.span(label) ])
    end
  end

  def refine_smoking_icon(icon)
    paths = {
      paper: '<path d="M18 12H2v4h16M22 12v4M6 12v4M18 8c0-1.5-1-2-2-3s-1-2 0-3M22 8c0-2-1-3-2-4"/>',
      heated: '<rect x="8" y="8" width="8" height="13" rx="3"/><path d="M10 8V4h4v4M11 2h2M11 17h2"/><circle cx="12" cy="12" r=".8" fill="currentColor" stroke="none"/>',
      seat: '<rect x="5" y="4" width="10" height="9" rx="3"/><path d="M4 11v5h12v-5M6 16v4M14 16v4M18 9h3M19 5c-2-1 2-2 0-3"/>',
      room: '<path d="M4 20V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v15M2 20h20"/><rect x="7" y="11" width="7" height="2.5" rx=".8"/><path d="M14 11h2v2.5h-2M16 8c-2-1 2-2 0-3"/>',
      non_smoking: '<circle cx="12" cy="12" r="10"/><path d="M5 5l14 14M4 13h12v3H4zM19 12v4M18 8c-2-1 2-2 0-3"/>',
      unknown: '<circle cx="12" cy="12" r="9"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 2-3 4M12 17h.01"/>'
    }
    # Only static, repository-owned SVG markup is marked safe.
    tag.svg(paths.fetch(icon).html_safe, width: 18, height: 18, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", 'stroke-width': 1.7, 'stroke-linecap': "round", 'stroke-linejoin': "round", aria: { hidden: true })
  end
end
