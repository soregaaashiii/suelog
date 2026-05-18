# /Users/kawamuratakuya/dev/suelog/script/site_insights.rb
# frozen_string_literal: true

require "csv"
require "fileutils"

GSC_CSV_PATH = Rails.root.join("tmp/insights/gsc_queries.csv")
GSC_QUERY_PAGES_CSV_PATH = Rails.root.join("tmp/insights/gsc_query_pages.csv")
GA4_CSV_PATH = Rails.root.join("tmp/insights/ga4_pages.csv")

GENRE_KEYWORDS = {
  "居酒屋" => %w[
    居酒屋
    酒場
    大衆酒場
    ネオ居酒屋
    飲み
    飲み屋
  ],
  "焼肉" => %w[焼肉 ホルモン],
  "焼鳥" => %w[焼鳥 焼き鳥 やきとり],
  "バー" => %w[バー bar],
  "カフェ" => %w[カフェ cafe],
  "喫茶店" => %w[喫茶 喫茶店 純喫茶],
  "ラーメン" => %w[ラーメン],
  "寿司" => %w[寿司 鮨],
  "シーシャ" => %w[
    シーシャ
    shisha
    hookah
  ],
  "個室" => %w[
    個室
    半個室
    完全個室
    2人個室
  ],
  "デート" => %w[
    デート
    雰囲気
    横並び
    記念日
    女子会
  ],
  "深夜" => %w[
    深夜
    朝まで
    始発
    24時間
    オール
  ],
  "安い" => %w[
    安い
    コスパ
    せんべろ
    食べ放題
    飲み放題
  ]
}.freeze

GENRE_DB_GROUPS = {
  "居酒屋" => %w[
    居酒屋
    酒場
    大衆酒場
    ネオ居酒屋
    立ち飲み
    立飲み
    焼鳥
    焼き鳥
    やきとり
    串焼き
    串焼
    串カツ
    串かつ
    串揚げ
    海鮮
    魚介
    和食
    創作料理
    ダイニングバー
  ],
  "焼鳥" => %w[
    焼鳥
    焼き鳥
    やきとり
    串焼き
    串焼
    鶏料理
    鶏肉料理
  ],
  "焼肉" => %w[
    焼肉
    焼き肉
    ホルモン
  ],
  "バー" => %w[
    バー
    BAR
    bar
    パブ
    ラウンジ
    ダイニングバー
    カラオケバー
  ],
  "カフェ" => %w[
    カフェ
    cafe
    Cafe
    喫茶
    喫茶店
    純喫茶
  ],
  "喫茶店" => %w[
    喫茶
    喫茶店
    純喫茶
    カフェ
  ],
  "寿司" => %w[
    寿司
    鮨
    すし
  ],
  "シーシャ" => %w[
    シーシャ
  ],
  "個室" => %w[
    個室
  ],
  "デート" => %w[
    居酒屋
    バー
    ダイニングバー
    イタリアン
    フレンチ
    焼肉
    シーシャ
    カフェ
  ],
  "深夜" => %w[
    居酒屋
    バー
    ダイニングバー
    焼肉
    シーシャ
    ラーメン
  ],
  "安い" => %w[
    居酒屋
    大衆酒場
    立ち飲み
    立飲み
    串カツ
    串かつ
    焼鳥
    焼き鳥
  ]
}.freeze

AREA_KEYWORDS = {
  "梅田" => %w[梅田 大阪駅 東通り お初天神 北新地 堂山 茶屋町],
  "難波" => %w[難波 なんば 心斎橋 道頓堀 日本橋],
  "京橋" => %w[京橋]
}.freeze

AREA_DB_ALIASES = {
  "梅田" => %w[
    梅田
    higashi_umeda
    umeda_higashidori
    umeda_kitashinchi
    umeda_chayamachi
    umeda_nakazakicho
    umeda_fukushima
    umeda_nakatsu
    umeda_tenma
    umeda_minamimorimachi
    umeda_honmachi_yodoyabashi
  ],

  "難波" => %w[
    難波
    namba
  ],

  "京橋" => %w[
    京橋
    kyobashi_main
  ]
}.freeze

NOISE_KEYWORDS = %w[
  クチコミ
  review
  reviews
  レビュー
  instagram
  インスタ
].freeze

FACILITY_SMOKING_KEYWORDS = %w[
  喫煙所
  喫煙スペース
  喫煙室
  喫煙エリア
].freeze

BRAND_LIKE_KEYWORDS = %w[
  the\ single
  ザシングル
  single
  neo
  queue
  kafka
  オリエンタルラウンジ
  バルチカ
  リンクス
  ルクア
  マヅラ
].freeze

REVENUE_FIT = {
  "焼肉" => 1.6,
  "居酒屋" => 1.5,
  "焼鳥" => 1.5,
  "個室" => 1.5,
  "デート" => 1.4,
  "深夜" => 1.4,
  "安い" => 1.3,
  "バー" => 1.2,
  "寿司" => 1.2,
  "シーシャ" => 1.1,
  "カフェ" => 0.9,
  "喫茶店" => 0.8,
  "ラーメン" => 0.8
}.freeze

CV_INTENT_KEYWORDS = {
  high: %w[
    喫煙可
    吸える
    紙タバコ
    紙たばこ
    席で吸える
    全席喫煙
    個室
    完全個室
    朝まで
    深夜
    今営業中
    営業中
    予約
    空席
  ],
  medium: %w[
    居酒屋
    バー
    焼肉
    焼鳥
    シーシャ
    デート
    横並び
    安い
    飲み放題
    せんべろ
  ],
  low: %w[
    クチコミ
    review
    reviews
    レビュー
    instagram
    インスタ
  ]
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
  normalized = query.to_s.downcase

  AREA_KEYWORDS.each do |area, keywords|
    return area if keywords.any? { |keyword| normalized.include?(keyword.downcase) }
  end

  return "梅田" if %w[
    東梅田
    西梅田
    北新地
    東通り
    お初天神
    堂山
    茶屋町
    太融寺
    中崎町
    福島
    中津
    南森町
  ].any? { |word| normalized.include?(word.downcase) }

  return "難波" if %w[
    なんば
    心斎橋
    道頓堀
    日本橋
  ].any? { |word| normalized.include?(word.downcase) }

  return "京橋" if %w[
    京橋
  ].any? { |word| normalized.include?(word.downcase) }

  nil
end

def detect_genre(query)
  normalized = query.to_s.downcase

  GENRE_KEYWORDS.each do |genre, keywords|
    return genre if keywords.any? { |keyword| normalized.include?(keyword.downcase) }
  end

  nil
end

def detect_cv_intent(query)
  normalized = query.to_s.downcase

  return "high" if CV_INTENT_KEYWORDS[:high].any? { |keyword| normalized.include?(keyword.downcase) }
  return "medium" if CV_INTENT_KEYWORDS[:medium].any? { |keyword| normalized.include?(keyword.downcase) }
  return "low" if CV_INTENT_KEYWORDS[:low].any? { |keyword| normalized.include?(keyword.downcase) }

  "unknown"
end

def looks_like_specific_shop_query?(query)
  normalized = query.to_s.downcase

  return false if normalized.include?("喫煙")
  return false if normalized.include?("タバコ")
  return false if normalized.include?("たばこ")
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

def detect_query_type(query)
  normalized = query.to_s.downcase

  return "facility_smoking" if FACILITY_SMOKING_KEYWORDS.any? { |keyword| normalized.include?(keyword.downcase) }
  return "brand_check" if BRAND_LIKE_KEYWORDS.any? { |keyword| normalized.include?(keyword.downcase) }
  return "specific_shop" if looks_like_specific_shop_query?(query)

  "general_seo"
end

def general_seo_query?(item)
  item[:query_type].to_s == "general_seo"
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

def cv_intent_multiplier(cv_intent)
  case cv_intent.to_s
  when "high"
    1.4
  when "medium"
    1.15
  when "low"
    0.7
  else
    1.0
  end
end

def expected_impact_score(
  impressions:,
  position:,
  ctr_percent:,
  supply_score:,
  revenue_fit:,
  cv_intent: "unknown"
)
  demand_score = impressions.to_f

  ranking_boost =
    case position.to_f
    when 1..3
      0.8
    when 4..10
      1.6
    when 11..20
      2.0
    when 21..50
      1.4
    else
      0.8
    end

  ctr_boost =
    case ctr_percent.to_f
    when 0...1
      2.0
    when 1...3
      1.6
    when 3...8
      1.2
    else
      0.8
    end

  shortage_boost =
    if supply_score <= 20
      2.0
    elsif supply_score <= 60
      1.5
    else
      1.0
    end

  (
    demand_score *
    ranking_boost *
    ctr_boost *
    shortage_boost *
    revenue_fit.to_f *
    cv_intent_multiplier(cv_intent)
  ).round(1)
end

def work_cost_for(action)
  case action.to_s
  when "CTR改善優先"
    1.0
  when "あと少し改善優先"
    1.2
  when "内部リンク・導線改善"
    1.5
  when "記事追加優先"
    3.0
  when "店舗追加優先"
    5.0
  else
    2.0
  end
end

def roi_score_for(expected_score:, action:)
  cost = work_cost_for(action)
  return 0 if cost <= 0

  (expected_score.to_f / cost).round(1)
end

def work_label_for(action)
  case action.to_s
  when "CTR改善優先"
    "低：title/meta改善中心"
  when "あと少し改善優先"
    "低〜中：タイトル・内部リンク・導線調整"
  when "内部リンク・導線改善"
    "低〜中：内部リンク・CTA調整"
  when "記事追加優先"
    "中：記事作成"
  when "店舗追加優先"
    "高：店舗収集・確認"
  else
    "中：確認作業"
  end
end

def apply_genre_group(scope, genre)
  return scope if genre.blank?

  terms = GENRE_DB_GROUPS[genre] || [genre]

  conditions = []
  binds = {}

  terms.each_with_index do |term, index|
    key = :"genre_term_#{index}"
    conditions << "(genre LIKE :#{key} OR genre_other LIKE :#{key})"
    binds[key] = "%#{term}%"
  end

  scope.where(conditions.join(" OR "), binds)
end

def shop_count_for(area:, genre:)
  scope = Shop.all

  if area.present?
    areas = AREA_DB_ALIASES[area] || [area]
    scope = scope.where(area: areas)
  end

  scope = apply_genre_group(scope, genre)
  scope.count
end

def confirmed_shop_count_for(area:, genre:)
  scope = Shop.where(smoking_unverified: [false, nil])

  if area.present?
    areas = AREA_DB_ALIASES[area] || [area]
    scope = scope.where(area: areas)
  end

  scope = apply_genre_group(scope, genre)
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

def read_ga4_pages
  return {} unless File.exist?(GA4_CSV_PATH)

  lines = File.readlines(GA4_CSV_PATH, encoding: "UTF-8")
  header_index = lines.index { |line| line.start_with?("ページパス") }
  return {} if header_index.nil?

  csv_text = lines[header_index..].join
  rows = CSV.parse(csv_text, headers: true)

  rows.each_with_object({}) do |row, hash|
    path = row["ページパス + クエリ文字列"].to_s.strip
    next if path.blank? || path == "合計"

    hash[path] = {
      views: row["表示回数"].to_i,
      active_users: row["アクティブ ユーザー"].to_i,
      engagement_seconds: row["アクティブ ユーザーあたりの平均エンゲージメント時間"].to_i,
      events: row["イベント数"].to_i
    }
  end
end

def read_gsc_query_pages
  return {} unless File.exist?(GSC_QUERY_PAGES_CSV_PATH)

  lines = File.readlines(GSC_QUERY_PAGES_CSV_PATH, encoding: "UTF-8")
  header_index = lines.index do |line|
    normalized_line =
      line.to_s
          .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          .strip

    next false if normalized_line.blank?

    normalized_line.include?("クエリ") ||
      normalized_line.include?("ページ") ||
      normalized_line.include?("URL") ||
      normalized_line.downcase.include?("query") ||
      normalized_line.downcase.include?("page")
  end

  return {} if header_index.nil?

  csv_text = lines[header_index..].join
  rows = CSV.parse(csv_text, headers: true)

  headers = rows.headers.map(&:to_s)

  page_header_exists =
    headers.any? do |header|
      normalized = normalize_header(header)

      normalized.include?("page") ||
        normalized.include?("ページ") ||
        normalized.include?("url")
    end

  unless page_header_exists
    puts
    puts "[WARN] gsc_query_pages.csv にページ列が存在しません"
    puts "[WARN] Search Consoleで「ページ」を追加した状態でエクスポートしてください"
    puts "[WARN] 現在のヘッダー:"
    pp headers

    return {}
  end

  grouped = Hash.new { |hash, key| hash[key] = [] }

  rows.each do |row|
    query = pick(row, [
      "query",
      "クエリ",
      "上位のクエリ",
      "検索クエリ"
    ]).to_s.strip

    page = pick(row, [
      "page",
      "ページ",
      "上位のページ",
      "ランディング ページ",
      "ランディングページ",
      "ページパス",
      "URL"
    ]).to_s.strip

    next if query.blank? || page.blank? || query == "合計" || page == "合計"

    clicks = pick(row, [
      "clicks",
      "クリック数",
      "クリック"
    ]).to_f

    impressions = pick(row, [
      "impressions",
      "表示回数",
      "表示"
    ]).to_f

    ctr_raw = pick(row, [
      "ctr",
      "CTR",
      "クリック率"
    ]).to_s.strip

    position = pick(row, [
      "position",
      "掲載順位",
      "平均掲載順位",
      "平均掲載順位"
    ]).to_f

    ctr_percent =
      if ctr_raw.include?("%")
        ctr_raw.delete("%").to_f
      elsif ctr_raw.to_f <= 1
        ctr_raw.to_f * 100
      else
        ctr_raw.to_f
      end

    grouped[query] << {
      page: page,
      clicks: clicks.to_i,
      impressions: impressions.to_i,
      ctr_percent: ctr_percent.round(2),
      position: position.round(1)
    }
  end

  grouped.transform_values do |items|
    items.max_by { |item| [item[:impressions].to_i, item[:clicks].to_i] }
  end
end

def article_ideas_for(item)
  area = item[:area]
  genre = item[:genre]

  return [] if area.blank? || genre.blank?

  base_ideas = [
    "#{area}で喫煙できる#{genre}まとめ",
    "#{area}で紙タバコが吸える#{genre}",
    "#{area}で深夜営業している喫煙#{genre}",
    "#{area}でデート向けの喫煙可能#{genre}",
    "#{area}でコスパがいい喫煙#{genre}"
  ]

  case genre
  when "デート"
    base_ideas.unshift(
      "#{area}で横並びデートできる喫煙OK店まとめ",
      "付き合う前でも行きやすい#{area}の喫煙OKデート店"
    )
  when "個室"
    base_ideas.unshift(
      "#{area}で個室喫煙できる居酒屋まとめ",
      "#{area}で2人個室がある喫煙OK店"
    )
  when "シーシャ"
    base_ideas.unshift(
      "#{area}のデート向けシーシャバーまとめ",
      "#{area}で個室ありのシーシャバーまとめ"
    )
  when "深夜"
    base_ideas.unshift(
      "#{area}で朝まで営業している喫煙可能店まとめ",
      "#{area}で深夜2時以降も吸える店まとめ"
    )
  end

  base_ideas.uniq
end

def recommendations_for(item)
  recommendations = []

  if item[:recommended_action] == "あと少し改善優先"
    recommendations << "順位8〜20位のため、タイトル改善・内部リンク追加・記事冒頭の結論強化を優先する"
  end

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

  recommendations.uniq
end

def todo_lines_for(item)
  lines = []

  case item[:recommended_action]
  when "CTR改善優先"
    lines << "SEOタイトルを喫煙意図に寄せて改善する"
    lines << "meta descriptionに「席で吸える」「紙タバコ」などを入れる"
  when "あと少し改善優先"
    lines << "該当LPのtitle/metaを検索意図に寄せて改善する"
    lines << "関連する記事・エリアページ・店舗ページから内部リンクを追加する"
    lines << "記事冒頭に結論店舗カードや条件リンクを追加する"
  when "店舗追加優先"
    if item[:area].present? && item[:genre].present?
      target_add_count =
        if item[:shops_count].to_i < 10
          30
        elsif item[:shops_count].to_i < 30
          20
        else
          10
        end

      lines << "#{item[:area]}の#{item[:genre]}店舗を+#{target_add_count}件追加する"
      lines << "#{item[:area]}の#{item[:genre]}店舗を優先的に電話確認する"
    else
      lines << "該当クエリに合う店舗カテゴリを確認してDBを増やす"
    end
  when "記事追加優先"
    article_ideas_for(item).first(2).each do |idea|
      lines << "記事作成：#{idea}"
    end
    lines << "既存記事から関連記事リンクを追加する"
  when "内部リンク・導線改善"
    lines << "記事冒頭に結論店舗カードを追加する"
    lines << "関連記事・店舗ページへの内部リンクを増やす"
  else
    lines << "該当ページを確認して小さく改善する"
  end

  lines.presence || ["該当クエリに合う既存ページを確認する"]
end

def print_recommendations(title, items, score_key, limit: 10)
  puts
  puts "=============================="
  puts title
  puts "=============================="

  items
    .reject { |item| item[:specific_shop_query] }
    .sort_by { |item| -item[score_key].to_f }
    .first(limit)
    .each_with_index do |item, index|
      puts
      puts "#{index + 1}. #{item[:query]}"
      puts "   優先スコア: #{item[score_key]}"
      puts "   状況: 表示#{item[:impressions]} / CTR#{item[:ctr_percent]}% / 順位#{item[:position]}"
      puts "   対象: #{item[:area] || '未判定'} / #{item[:genre] || '未判定'} / CV意図: #{item[:cv_intent]}"
      puts "   供給: DB店舗#{item[:shops_count]} / 確認済み#{item[:confirmed_count]} / 記事#{item[:articles_count]}"
      puts "   推奨施策:"
      recommendations_for(item).each do |recommendation|
        puts "   - #{recommendation}"
      end

      article_ideas = article_ideas_for(item)

      if article_ideas.any?
        puts "   推奨記事:"
        article_ideas.first(3).each do |idea|
          puts "   * #{idea}"
        end
      end
    end
end

def print_todo_section(title, items, limit: 10)
  puts
  puts "=============================="
  puts title
  puts "=============================="

  items
    .reject { |item| item[:specific_shop_query] }
    .sort_by { |item| [-item[:roi_score].to_f, -item[:expected_score].to_f] }
    .first(limit)
    .each_with_index do |item, index|
      puts
      puts "#{index + 1}. #{item[:query]}"
      puts "   ROI: #{item[:roi_score]} / 期待値: #{item[:expected_score]} / 作業コスト: #{item[:work_label]}"
      puts "   推奨施策: #{item[:recommended_action]} / CV意図: #{item[:cv_intent]}"
      puts "   TODO:"
      todo_lines_for(item).each do |line|
        puts "   - #{line}"
      end
    end
end

def print_ga4_pages(title, ga4_pages, limit: 15)
  puts
  puts "=============================="
  puts title
  puts "=============================="

  ga4_pages
    .sort_by { |path, data| [-data[:views].to_i, path] }
    .first(limit)
    .each_with_index do |(path, data), index|
      puts
      puts "#{index + 1}. #{path}"
      puts "   PV: #{data[:views].to_i} / Active: #{data[:active_users].to_i} / 滞在: #{data[:engagement_seconds].to_f.round(1)}秒 / Events: #{data[:events].to_i}"

      if path.start_with?("/articles/")
        puts "   判定: 記事ページ。店舗カード導線・関連記事・CTAを確認する"
      elsif path.start_with?("/shops/")
        puts "   判定: 店舗ページ。電話・地図・予約クリック導線を確認する"
      elsif path == "/" || path.start_with?("/umeda") || path.start_with?("/namba")
        puts "   判定: 一覧/エリアページ。検索条件導線と内部リンクを確認する"
      else
        puts "   判定: その他ページ。流入意図を確認する"
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

  target_items.sort_by { |item| -item[score_key].to_f }.first(limit).each_with_index do |item, index|
    puts
    puts "#{index + 1}. #{item[:query]}"
    puts "   score: #{item[score_key]}"
    puts "   表示: #{item[:impressions]} / クリック: #{item[:clicks]} / CTR: #{item[:ctr_percent]}% / 順位: #{item[:position]}"
    puts "   area: #{item[:area] || '未判定'} / genre: #{item[:genre] || '未判定'} / CV意図: #{item[:cv_intent]}"
    puts "   DB集計ジャンル: #{item[:genre].present? ? (GENRE_DB_GROUPS[item[:genre]] || [item[:genre]]).join(' / ') : '未判定'}"
    puts "   DB店舗: #{item[:shops_count]} / 確認済み: #{item[:confirmed_count]} / 記事数: #{item[:articles_count]}"

    if item[:landing_page].present?
      puts "   LP: #{item[:landing_page]} / LP表示: #{item[:lp_impressions]} / LPクリック: #{item[:lp_clicks]} / LP CTR: #{item[:lp_ctr_percent]}% / LP順位: #{item[:lp_position]}"
    else
      puts "   LP: 未取得"
    end

    puts "   GA4: PV#{item[:ga4_views]} / Active#{item[:ga4_active_users]} / 滞在#{item[:ga4_engagement_seconds]}秒"
    puts "   期待値: #{item[:expected_score]} / ROI: #{item[:roi_score]} / 推奨施策: #{item[:recommended_action]}"
    puts "   作業コスト: #{item[:work_label]}"
  end
end

def write_next_actions_csv(items)
  output_dir = Rails.root.join("tmp/insights")
  FileUtils.mkdir_p(output_dir)

  next_actions_path = output_dir.join("next_actions.csv")

  CSV.open(next_actions_path, "w") do |csv|
    csv << [
      "query",
      "area",
      "genre",
      "cv_intent",
      "query_type",
      "recommended_action",
      "expected_score",
      "roi_score",
      "work_label",
      "impressions",
      "clicks",
      "ctr_percent",
      "position",
      "landing_page",
      "shops_count",
      "confirmed_count",
      "articles_count",
      "todo"
    ]

    items
      .reject { |item| item[:specific_shop_query] }
      .sort_by { |item| [-item[:roi_score].to_f, -item[:expected_score].to_f] }
      .first(200)
      .each do |item|
        csv << [
          item[:query],
          item[:area],
          item[:genre],
          item[:cv_intent],
          item[:query_type],
          item[:recommended_action],
          item[:expected_score],
          item[:roi_score],
          item[:work_label],
          item[:impressions],
          item[:clicks],
          item[:ctr_percent],
          item[:position],
          item[:landing_page],
          item[:shops_count],
          item[:confirmed_count],
          item[:articles_count],
          todo_lines_for(item).join(" / ")
        ]
      end
  end

  next_actions_path
end

unless File.exist?(GSC_CSV_PATH)
  puts "GSC CSVがありません: #{GSC_CSV_PATH}"
  puts
  puts "Google Search ConsoleからクエリCSVを落として、次の名前で置いてください。"
  puts "tmp/insights/gsc_queries.csv"
  exit 1
end

rows = CSV.read(GSC_CSV_PATH, headers: true, encoding: "UTF-8")
ga4_pages = read_ga4_pages
query_pages = read_gsc_query_pages

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
  cv_intent = detect_cv_intent(query)

  next if impressions <= 0

  query_downcase = query.downcase

  next if NOISE_KEYWORDS.any? { |keyword| query_downcase.include?(keyword.downcase) }

  specific_shop_query = looks_like_specific_shop_query?(query)
  query_type = detect_query_type(query)

  demand_score = impressions + (clicks * 5)
  growth_score = position_multiplier(position) * ctr_multiplier(ctr_percent)
  revenue_fit = REVENUE_FIT.fetch(genre, 1.0) * cv_intent_multiplier(cv_intent)

  shops_count = shop_count_for(area: area, genre: genre)
  confirmed_count = confirmed_shop_count_for(area: area, genre: genre)
  articles_count = article_count_for(area: area, genre: genre)

  supply_score = shops_count + (confirmed_count * 2) + (articles_count * 20)
  supply_score = 5 if supply_score < 5

  pv_score = demand_score * growth_score
  revenue_score = demand_score * growth_score * revenue_fit
  db_gap_score = demand_score / supply_score
  ctr_score = impressions * ctr_multiplier(ctr_percent)

  expected_score =
    expected_impact_score(
      impressions: impressions,
      position: position,
      ctr_percent: ctr_percent,
      supply_score: supply_score,
      revenue_fit: revenue_fit,
      cv_intent: cv_intent
    )

  lp_data = query_pages[query] || {}
  landing_page = lp_data[:page].to_s
  ga4_data = ga4_pages[landing_page] || {}

  near_win =
    position >= 8 &&
    position <= 20 &&
    impressions >= 30

  recommended_action =
    if near_win
      "あと少し改善優先"
    elsif position <= 10 && ctr_percent < 1.5
      "CTR改善優先"
    elsif shops_count <= 15
      "店舗追加優先"
    elsif articles_count <= 1
      "記事追加優先"
    elsif ga4_data[:views].to_i > 0 && ga4_data[:engagement_seconds].to_f < 15
      "内部リンク・導線改善"
    else
      "維持・微改善"
    end

  work_cost = work_cost_for(recommended_action)
  roi_score = roi_score_for(expected_score: expected_score, action: recommended_action)
  work_label = work_label_for(recommended_action)

  {
    query: query,
    area: area,
    genre: genre,
    cv_intent: cv_intent,
    query_type: query_type,
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
    ctr_score: ctr_score.round(1),
    expected_score: expected_score,
    recommended_action: recommended_action,
    work_cost: work_cost,
    roi_score: roi_score,
    work_label: work_label,
    landing_page: landing_page,
    lp_clicks: lp_data[:clicks].to_i,
    lp_impressions: lp_data[:impressions].to_i,
    lp_ctr_percent: lp_data[:ctr_percent].to_f,
    lp_position: lp_data[:position].to_f,
    ga4_views: ga4_data[:views].to_i,
    ga4_active_users: ga4_data[:active_users].to_i,
    ga4_engagement_seconds: ga4_data[:engagement_seconds].to_f.round(1)
  }
end

puts
puts "吸えログ施策レポート"
puts "CSV: #{GSC_CSV_PATH}"
puts "対象クエリ数: #{items.size}"
puts "GSCページ×クエリ数: #{query_pages.size}"
puts "GA4ページ数: #{ga4_pages.size}"

puts
puts "エリア別DB件数"

AREA_DB_ALIASES.each do |area, aliases|
  count = Shop.where(area: aliases).count
  puts "- #{area}: #{count}件"
end

general_seo_items = items.select { |item| general_seo_query?(item) }

print_section("一般検索：本当に伸ばすべきSEO", general_seo_items, :revenue_score)
print_section("PV最大化：流入を増やすなら優先", items, :pv_score)
print_section("収益最大化：送客・予約につなげるなら優先", items, :revenue_score)
print_section("DB強化：検索需要に対して店舗DBが弱い候補", items, :db_gap_score)
print_section("CTR改善：表示はあるのにクリックを取り切れていない候補", items, :ctr_score)

print_section("最優先施策：期待値が高い順", items, :expected_score)

print_todo_section("自動TODO：ROIが高い順", items)

print_section("店舗名系：個別店舗ページ・記事で拾えている検索", items.select { |item| item[:query_type] == "specific_shop" }, :pv_score, general_only: false)
print_section("確認検索っぽいブランド系：優先順位から分離", items.select { |item| item[:query_type] == "brand_check" }, :pv_score, general_only: false)
print_section("喫煙所系：飲食送客SEOとは分離", items.select { |item| item[:query_type] == "facility_smoking" }, :pv_score, general_only: false)

print_ga4_pages("GA4：よく見られているページ", ga4_pages)

print_recommendations("自動施策提案：今すぐやる候補", items, :revenue_score)

next_actions_path = write_next_actions_csv(items)

puts
puts "生成CSV"
puts "- #{next_actions_path.relative_path_from(Rails.root)}"

puts
puts "次の見方"
puts "- PV最大化：記事追加・タイトル改善・内部リンク強化"
puts "- 収益最大化：予約導線、アフィリエイト、店舗カード改善"
puts "- DB強化：該当ジャンル/エリアの店舗追加、電話確認"
puts "- CTR改善：SEOタイトル、meta description、記事冒頭の訴求改善"
puts "- 生成CSV：tmp/insights/next_actions.csv を見れば次施策を一覧で確認できます"