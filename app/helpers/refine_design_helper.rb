module RefineDesignHelper
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
      unknown: '<circle cx="12" cy="12" r="9"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 2-3 4M12 17h.01"/>'
    }
    # Only static, repository-owned SVG markup is marked safe.
    tag.svg(paths.fetch(icon).html_safe, width: 18, height: 18, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", 'stroke-width': 1.7, 'stroke-linecap': "round", 'stroke-linejoin': "round", aria: { hidden: true })
  end
end
