module RefineDesignHelper
  def refine_smoking_badges(area, type)
    safe_join([refine_smoking_badge(:area, area), refine_smoking_badge(:type, type)], ' ')
  end

  def refine_smoking_badge(kind, value)
    state, label, icons = if kind == :area
      { 'all_smoking' => ['seat', '席で喫煙可', [:seat]],
        'separated' => ['room', '喫煙所あり', [:room]] }.fetch(value.to_s, ['unknown', '喫煙場所不明', [:unknown]])
    else
      { 'both_ok' => ['both', '紙・加熱式OK', [:paper, :heated]],
        'electronic_only' => ['heated', '加熱式のみ', [:heated]],
        'paper_only' => ['paper', '紙のみ', [:paper]] }.fetch(value.to_s, ['unknown', 'たばこ種類不明', [:unknown]])
    end
    tag.span(class: "smoking-badge smoking-badge--#{state}") do
      safe_join([tag.span(safe_join(icons.map { |icon| refine_smoking_icon(icon) }), class: 'smoking-badge-icons', aria: { hidden: true }), tag.span(label)])
    end
  end

  def refine_smoking_icon(icon)
    paths = {
      paper: '<path d="M18 12H2v4h16M22 12v4M6 12v4M18 8c0-1.5-1-2-2-3s-1-2 0-3M22 8c0-2-1-3-2-4"/>',
      heated: '<rect x="8" y="8" width="8" height="13" rx="3"/><path d="M10 8V4h4v4M11 2h2M11 17h2"/><circle cx="12" cy="12" r=".8" fill="currentColor" stroke="none"/>',
      seat: '<rect x="5" y="4" width="10" height="9" rx="3"/><path d="M4 11v5h12v-5M6 16v4M14 16v4M18 9h3M19 5c-2-1 2-2 0-3"/>',
      room: '<path d="M4 20V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v15M2 20h20"/><rect x="7" y="11" width="7" height="2.5" rx=".8"/><path d="M14 11h2v2.5h-2M16 8c-2-1 2-2 0-3"/>',
      unknown: '<circle cx="12" cy="12" r="9"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 2-3 4M12 17h.01"/>'
    }
    # Only static, repository-owned SVG markup is marked safe.
    tag.svg(paths.fetch(icon).html_safe, width: 18, height: 18, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', 'stroke-width': 1.7, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', aria: { hidden: true })
  end
end
