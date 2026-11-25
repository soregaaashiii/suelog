# frozen_string_literal: true

module Admin::SeoPagesHelper
  def seo_metric_value(metric, key)
    return "—" unless metric && !metric[key].nil?
    case key
    when :ctr then "#{number_with_precision(metric[key], precision: 2)}%"
    when :position then number_with_precision(metric[key], precision: 2)
    else number_with_delimiter(metric[key])
    end
  end

  def seo_metric_change(deltas, key)
    return "比較なし" unless deltas && !deltas[key].nil?
    value = deltas[key]
    amount = %i[ctr position].include?(key) ? number_with_precision(value, precision: 2) : number_with_delimiter(value)
    "前期間比 #{value.positive? ? '+' : ''}#{amount}#{key == :ctr ? 'pt' : ''}"
  end
end
