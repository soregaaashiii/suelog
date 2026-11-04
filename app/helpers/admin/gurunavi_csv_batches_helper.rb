module Admin::GurunaviCsvBatchesHelper
  def csv_difference(value, other)
    left, right = value.to_s.chars, other.to_s.chars
    return "（空欄）" if left.empty?
    return value.to_s if left == right
    prefix = 0
    prefix += 1 while prefix < [ left.size, right.size ].min && left[prefix] == right[prefix]
    suffix = 0
    suffix += 1 while suffix < [ left.size, right.size ].min - prefix && left[-suffix - 1] == right[-suffix - 1]
    safe_join([ left.first(prefix).join, content_tag(:span, left[prefix, left.size - prefix - suffix].join, class: "csv-difference", style: "color:#b42318;background:#fff0f0;border-bottom:2px solid #b42318;", title: "相手側の表記と異なる部分"), suffix.zero? ? "" : left.last(suffix).join ])
  end
end
