# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/lib/recalc_approval_for_imported_shops.rb
# frozen_string_literal: true

# 対象をどう絞るか：
# - source カラムがあるなら source="google" を対象
# - 無い場合は note に「【自動取込】」が入ってるものを対象
scope =
  if Shop.column_names.include?("source")
    Shop.where(source: "google")
  else
    Shop.where("note LIKE ?", "%【自動取込】%")
  end

total = scope.count
puts "TARGET total=#{total}"

# ① まず全部 pending に戻す
reset = scope.update_all(
  approved: false,
  rejected: false,
  updated_at: Time.current
)
puts "RESET pending=#{reset}"

# ② 不明がないものだけ approved=true に戻す
approved = 0
kept_pending = 0

scope.find_each do |shop|
  missing = []
  missing << "営業時間" if shop.opening_hours.blank?
  missing << "最寄駅" if shop.nearest_station.blank?
  missing << "喫煙エリア" if shop.smoking_area.blank?
  missing << "喫煙タイプ" if shop.smoking_type.blank?

  # noteに「不明」が残ってたら pending にする（保険）
  unknown_in_note = shop.note.to_s.include?("【自動取込】不明:")

  if missing.any? || unknown_in_note
    # pendingのまま
    kept_pending += 1

    # 何が不明か note に追記（既に同じ行があれば増やさない）
    if missing.any?
      line = "【再判定】不明: #{missing.join(' / ')}"
      note = shop.note.to_s
      unless note.include?(line)
        new_note = [note.strip, line].reject(&:blank?).join("\n")
        shop.update_columns(note: new_note, updated_at: Time.current)
      end
    end

    next
  end

  shop.update_columns(approved: true, rejected: false, updated_at: Time.current)
  approved += 1
end

puts "DONE approved=#{approved} kept_pending=#{kept_pending}"
