# /Users/kawamuratakuya/dev/suelog/script/site_insights.rb
# frozen_string_literal: true

require "csv"

GSC_CSV_PATH = Rails.root.join("tmp/insights/gsc_queries.csv")

GENRE_KEYWORDS = {
  "居酒屋" => %w[居酒屋 酒場 飲み 飲み屋],
  "焼肉" => %w[焼肉 ホルモン],
  "焼鳥" => %w[焼鳥 焼き鳥 やきとり],
  "バー" => %w[バー bar],
  "カフェ" => %w[カフェ cafe],
  "喫茶店" => %w[喫茶 喫茶店 純喫茶],
  "ラーメン" => %w[ラーメン],
  "寿司" => %w[寿司 鮨],
  "シーシャ" => %w[シーシャ],
  "個室" => %w[個室],
  "デート" => %w[デート 雰囲気 横並び]
}.freeze


AREA_KEYWORDS = {
  "梅田" => %w[梅田 大阪駅 東通り お初天神 北新地 堂山 茶屋町],
  "難波" => %w[難波 なんば 心斎橋 道頓堀 日本橋]
}.freeze

NOISE_KEYWORDS = %w[
  クチコミ
  review
  reviews
  レビュー
  instagram
  インスタ
].freeze

REVENUE_FIT = {
  "焼肉" => 1.6,
  "居酒屋" => 1.5,
  "焼鳥" => 1.5,
  "個室" => 1.5,
  "デート" => 1.4,
  "バー" => 1.2,
  "寿司" => 1.2,
  "シーシャ" => 1.1,
  "カフェ" => 0.9,
  "喫茶店" => 0.8,
  "ラーメン" => 0.8
}.freeze

def normalize_header(header)
  header.to_s
        .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        .sub(/\A\uFEFF/, "")
        .strip
        .downcase
end

def pick(row, keys)
  normalized = row.to_h.transform_keys { |k| normalize_header(k) }

  keys.each do |key|
    value = normalized[normalize_header(key)]
    return value if value.present?
  end

  nil
end

def detect_area(query)
  AREA_KEYWORDS.each do |area, keywords|
    return area if keywords.any? { |keyword| query.include?(keyword) }
  end

  nil
end

def detect_genre(query)
  GENRE_KEYWORDS.each do |genre, keywords|
    return genre if keywords.any? { |keyword| query.downcase.include?(keyword.downcase) }
  end

  nil
end

def looks_like_specific_shop_query?(query)
  normalized = query.to_s.downcase

  return false if normalized.include?("喫煙")
  return false if normalized.include?("タバコ")
  return false if normalized.include?("吸える")
  return false if normalized.include?("喫煙可")

  shop_like_words = %w[
    cafe
    bar
    dining
    lounge
    shisha
    coffee
    bistro
    restaurant
    口コミ
    クチコミ
    レビュー
  ]

  return true if shop_like_words.any? { |word| normalized.include?(word) }

  words = normalized.split(/[ 　]/)
  words.size <= 3
end

def position_multiplier(position)
  case position.to_f
  when 1..3
    0.6
  when 4..7
    1.0
  when 8..20
    1.6
  when 21..50
    1.2
  else
    0.7
  end
end

def ctr_multiplier(ctr_percent)
  case ctr_percent.to_f
  when 0...1
    1.6
  when 1...3
    1.3
  when 3...8
    1.0
  else
    0.7
  end
end

def shop_count_for(area:, genre:)
  scope = Shop.all
  scope = scope.where(area: area) if area.present?
  scope = scope.where("genre LIKE ?", "%#{genre}%") if genre.present?
  scope.count
end

def confirmed_shop_count_for(area:, genre:)
  scope = Shop.where(smoking_unverified: [false, nil])
  scope = scope.where(area: area) if area.present?
  scope = scope.where("genre LIKE ?", "%#{genre}%") if genre.present?
  scope.count
end

def article_count_for(area:, genre:)
  return 0 unless defined?(Article)

  terms = [area, genre].compact
  return 0 if terms.empty?

  scope = Article.all
  terms.each do |term|
    scope = scope.where("title LIKE :term OR slug LIKE :term", term: "%#{term}%")
  end
  scope.count
end

unless File.exist?(GSC_CSV_PATH)
  puts "GSC CSVがありません: #{GSC_CSV_PATH}"
  puts
  puts "Google Search ConsoleからクエリCSVを落として、次の名前で置いてください。"
  puts "tmp/insights/gsc_queries.csv"
  exit 1
end

rows = CSV.read(GSC_CSV_PATH, headers: true, encoding: "UTF-8")

items = rows.filter_map do |row|
  query = pick(row, ["query", "クエリ", "上位のクエリ"]).to_s.strip
  next if query.blank?

  clicks = pick(row, ["clicks", "クリック数"]).to_f
  impressions = pick(row, ["impressions", "表示回数"]).to_f
  ctr_raw = pick(row, ["ctr", "CTR"]).to_s.strip
  position = pick(row, ["position", "掲載順位", "平均掲載順位"]).to_f

  ctr_percent =
    if ctr_raw.include?("%")
      ctr_raw.delete("%").to_f
    elsif ctr_raw.to_f <= 1
      ctr_raw.to_f * 100
    else
      ctr_raw.to_f
    end

  area = detect_area(query)
  genre = detect_genre(query)

  next if impressions <= 0

  query_downcase = query.downcase

  next if NOISE_KEYWORDS.any? { |keyword| query_downcase.include?(keyword.downcase) }

  specific_shop_query = looks_like_specific_shop_query?(query)

  demand_score = impressions + (clicks * 5)
  growth_score = position_multiplier(position) * ctr_multiplier(ctr_percent)
  revenue_fit = REVENUE_FIT.fetch(genre, 1.0)

  shops_count = shop_count_for(area: area, genre: genre)
  confirmed_count = confirmed_shop_count_for(area: area, genre: genre)
  articles_count = article_count_for(area: area, genre: genre)

  supply_score = shops_count + (confirmed_count * 2) + (articles_count * 20)
  supply_score = 5 if supply_score < 5

  pv_score = demand_score * growth_score
  revenue_score = demand_score * growth_score * revenue_fit
  db_gap_score = demand_score / supply_score
  ctr_score = impressions * ctr_multiplier(ctr_percent)

  {
    query: query,
    area: area,
    genre: genre,
    specific_shop_query: specific_shop_query,
    clicks: clicks.to_i,
    impressions: impressions.to_i,
    ctr_percent: ctr_percent.round(2),
    position: position.round(1),
    shops_count: shops_count,
    confirmed_count: confirmed_count,
    articles_count: articles_count,
    pv_score: pv_score.round(1),
    revenue_score: revenue_score.round(1),
    db_gap_score: db_gap_score.round(1),
    ctr_score: ctr_score.round(1)
  }
end

def recommendations_for(item)
  recommendations = []

  if item[:shops_count].to_i < 20 && item[:area].present? && item[:genre].present?
    recommendations << "#{item[:area]}の#{item[:genre]}店舗を追加収集する"
  end

  if item[:confirmed_count].to_i < 10 && item[:shops_count].to_i.positive?
    recommendations << "既存店舗の電話確認・喫煙情報確認を増やす"
  end

  if item[:articles_count].to_i.zero? && item[:area].present? && item[:genre].present?
    recommendations << "「#{item[:area]}で喫煙できる#{item[:genre]}まとめ」記事を作る"
  end

  if item[:ctr_percent].to_f < 2.0 && item[:impressions].to_i >= 30
    recommendations << "SEOタイトル・meta descriptionを改善する"
  end

  if item[:position].to_f >= 8 && item[:position].to_f <= 30
    recommendations << "関連ページから内部リンクを追加する"
  end

  recommendations << "該当クエリに合う既存ページを確認して導線を強化する" if recommendations.empty?

  recommendations
end

def print_recommendations(title, items, score_key, limit: 10)
  puts
  puts "=============================="
  puts title
  puts "=============================="

  items
    .reject { |item| item[:specific_shop_query] }
    .sort_by { |item| -item[score_key] }
    .first(limit)
    .each_with_index do |item, index|
      puts
      puts "#{index + 1}. #{item[:query]}"
      puts "   優先スコア: #{item[score_key]}"
      puts "   状況: 表示#{item[:impressions]} / CTR#{item[:ctr_percent]}% / 順位#{item[:position]}"
      puts "   対象: #{item[:area] || '未判定'} / #{item[:genre] || '未判定'}"
      puts "   供給: DB店舗#{item[:shops_count]} / 確認済み#{item[:confirmed_count]} / 記事#{item[:articles_count]}"
      puts "   推奨施策:"
      recommendations_for(item).each do |recommendation|
        puts "   - #{recommendation}"
      end
    end
end

def print_section(title, items, score_key, limit: 10, general_only: true)
  puts
  puts "=============================="
  puts title
  puts "=============================="

  target_items =
    if general_only
      items.reject { |item| item[:specific_shop_query] }
    else
      items
    end

  target_items.sort_by { |item| -item[score_key] }.first(limit).each_with_index do |item, index|
    puts
    puts "#{index + 1}. #{item[:query]}"
    puts "   score: #{item[score_key]}"
    puts "   表示: #{item[:impressions]} / クリック: #{item[:clicks]} / CTR: #{item[:ctr_percent]}% / 順位: #{item[:position]}"
    puts "   area: #{item[:area] || '未判定'} / genre: #{item[:genre] || '未判定'}"
    puts "   DB店舗: #{item[:shops_count]} / 確認済み: #{item[:confirmed_count]} / 記事数: #{item[:articles_count]}"
  end
end

puts
puts "吸えログ施策レポート"
puts "CSV: #{GSC_CSV_PATH}"
puts "対象クエリ数: #{items.size}"

print_section("PV最大化：流入を増やすなら優先", items, :pv_score)
print_section("収益最大化：送客・予約につなげるなら優先", items, :revenue_score)
print_section("DB強化：検索需要に対して店舗DBが弱い候補", items, :db_gap_score)
print_section("CTR改善：表示はあるのにクリックを取り切れていない候補", items, :ctr_score)
print_section("店舗名系：個別店舗ページ・記事で拾えている検索", items.select { |item| item[:specific_shop_query] }, :pv_score, general_only: false)

print_recommendations("自動施策提案：今すぐやる候補", items, :revenue_score)

puts
puts "次の見方"
puts "- PV最大化：記事追加・タイトル改善・内部リンク強化"
puts "- 収益最大化：予約導線、アフィリエイト、店舗カード改善"
puts "- DB強化：該当ジャンル/エリアの店舗追加、電話確認"
puts "- CTR改善：SEOタイトル、meta description、記事冒頭の訴求改善"