module GurunaviCsv
  module Confidence
    module_function
    LABELS = { 400 => "店名・住所が完全一致", 300 => "店名の別名表記・住所が一致", 200 => "番地一致・店名が類似", 100 => "店名類似・住所などを要確認", 0 => "候補なし" }.freeze
    def variants(value)
      full = Normalizer.name(value)
      base = Normalizer.name(value.to_s.sub(/\s*[（(](?:【旧店名】[^）)]*|[a-zA-Z][a-zA-Z\s&.-]*)[）)]\s*\z/, ""))
      [ full, base ].reject(&:blank?).uniq
    end
    def name_similarity(a, b)
      return 1.0 if a == b
      suffix = a.chars.reverse.zip(b.chars.reverse).take_while { |x, y| x == y }.size
      # A shared building/branch suffix alone is not evidence of the same restaurant.
      if suffix >= 4
        left, right = a.chars[0...-suffix].join, b.chars[0...-suffix].join
        return Normalizer.similarity(left, right) if left.present? && right.present?
      end
      Normalizer.similarity(a, b)
    end
    def score(name, address, csv_name, csv_address)
      return 0 if [ name, address, csv_name, csv_address ].any?(&:blank?)
      same_address = Normalizer.address(address) == Normalizer.address(csv_address)
      names = variants(name).product(variants(csv_name))
      similarity = names.map { |a, b| name_similarity(a, b) }.max.to_f
      same_name = Normalizer.name(name) == Normalizer.name(csv_name)
      alias_name = names.any? { |a, b| a == b }
      same_street = Normalizer.complete?(address) && Normalizer.complete?(csv_address) && Normalizer.street(address) == Normalizer.street(csv_address)
      same_city = Normalizer.municipality(address).present? && Normalizer.municipality(address) == Normalizer.municipality(csv_address)
      result = if same_name && same_address then 400
      elsif alias_name && same_address then 300
      elsif same_street && (alias_name || similarity >= 0.45) then 200
      elsif same_city && (alias_name || similarity >= 0.7) then 100
      else 0
      end
      # Missing floors remain a confirmation candidate; explicit different floors never rank highly.
      floors = [ address, csv_address ].map { |a| Normalizer.text(a).scan(/(?:b|地下)?\d+(?:f|階)/).map { |f| f.tr("階", "f").sub("地下", "b") }.flatten.uniq }
      result = [ result, 100 ].min if floors.all?(&:any?) && (floors[0] & floors[1]).empty?
      result
    end
    def label(score) = LABELS.fetch(score.to_i, LABELS[100])
  end
end
