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
  "梅田" => %w[梅田 大阪駅 東通り お初天神 北新地 堂山 茶屋町 中之島 福島 天満 中崎町 中津 南森町 西天満],
  "難波" => %w[難波 なんば 心斎橋 道頓堀 日本橋 千日前 大国町],
  "京橋" => %w[京橋],
  "西中島" => %w[西中島 西中島南方 南方 新大阪],
  "本町" => %w[本町 淀屋橋 北浜 肥後橋]
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
  ],

  "西中島" => %w[
    西中島
    nishinakajima
  ],

  "本町" => %w[
    本町
    honmachi
    umeda_honmachi_yodoyabashi
  ]
}.freeze

LOCAL_AREA_KEYWORDS = {
  "曽根崎" => %w[
    曽根崎
    お初天神
    東梅田
    太融寺
  ],
  "東通り" => %w[
    東通り
    堂山
    小松原
    阪急東通
  ],
  "お初天神" => %w[
    お初天神
    曽根崎
    露天神
  ],
  "東梅田" => %w[
    東梅田
    曽根崎
    太融寺
    堂山
  ],
  "北新地" => %w[
    北新地
    曽根崎新地
  ],
  "堂山" => %w[
    堂山
    東通り
    太融寺
  ],
  "茶屋町" => %w[
    茶屋町
    芝田
  ],
  "太融寺" => %w[
    太融寺
    堂山
    東梅田
  ],
  "大阪駅" => %w[
    大阪駅
    梅田
    芝田
    大深町
  ],
  "日本橋" => %w[
    日本橋
    千日前
  ],
  "心斎橋" => %w[
    心斎橋
    東心斎橋
    西心斎橋
  ],
  "道頓堀" => %w[
    道頓堀
    宗右衛門町
  ],
  "中之島" => %w[
    中之島
    堂島
    渡辺橋
    肥後橋
  ],
  "福島" => %w[
    福島
    新福島
    野田
    海老江
  ],
  "天満" => %w[
    天満
    天神橋筋六丁目
    天六
    扇町
  ],
  "中崎町" => %w[
    中崎町
    中崎
  ],
  "中津" => %w[
    中津
    豊崎
  ],
  "南森町" => %w[
    南森町
    大阪天満宮
    西天満
  ],
  "西中島" => %w[
    西中島
    西中島南方
    南方
    新大阪
  ],
  "本町" => %w[
    本町
    淀屋橋
    北浜
    肥後橋
  ],
  "大国町" => %w[
    大国町
    敷津
    今宮
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
  ドトール
  勝男
  餃子のかっちゃん
  鉄板神社
  晩杯屋
  鳥貴族
  磯丸水産
  HUB
  hub
  サンマルク
  スターバックス
  タリーズ
  コメダ
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

def detect_local_area(query)
  normalized = query.to_s.downcase

  LOCAL_AREA_KEYWORDS.each do |local_area, keywords|
    return local_area if keywords.any? { |keyword| normalized.include?(keyword.downcase) }
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
    中之島
    堂島
    西天満
    天満
    天六
    扇町
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

  return "西中島" if %w[
    西中島
    西中島南方
    南方
    新大阪
  ].any? { |word| normalized.include?(word.downcase) }

  return "本町" if %w[
    本町
    淀屋橋
    北浜
    肥後橋
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

def detect_theme(query:, landing_page: nil)
  text = [query, landing_page].compact.join(" ").downcase

  return "デート" if text.match?(/デート|横並び|記念日|雰囲気|2人|二人|yokonarabi|date/)
  return "シーシャ" if text.match?(/シーシャ|shisha|hookah/)
  return "個室" if text.match?(/個室|private-room/)
  return "バー" if text.match?(/バー|bar/)
  return "居酒屋" if text.match?(/居酒屋|izakaya/)
  return "喫煙所" if text.match?(/喫煙所|喫煙スペース|喫煙室/)

  nil
end

def detect_cv_intent(query)
  normalized = query.to_s.downcase

  return "high" if CV_INTENT_KEYWORDS[:high].any? { |keyword| normalized.include?(keyword.downcase) }
  return "medium" if CV_INTENT_KEYWORDS[:medium].any? { |keyword| normalized.include?(keyword.downcase) }
  return "low" if CV_INTENT_KEYWORDS[:low].any? { |keyword| normalized.include?(keyword.downcase) }

  "unknown"
end

def unnatural_query?(query)
  normalized = query.to_s.downcase.strip

  return true if normalized.include?("とは") && !normalized.include?("喫煙")
  return true if normalized.match?(/[&×]/) && !normalized.include?("喫煙")
  return true if normalized.match?(/[ａ-ｚＡ-Ｚ]/)

  words = normalized.split(/[ 　]/).reject(&:blank?)

  return true if words.size >= 4 && !normalized.match?(/喫煙|タバコ|たばこ|吸える|喫煙可|個室|深夜|朝まで|飲み放題/)

  false
end

def looks_like_specific_shop_query?(query)
  normalized = query.to_s.downcase

  return true if unnatural_query?(query)

  explicit_smoking_intent =
    normalized.include?("喫煙") ||
    normalized.include?("タバコ") ||
    normalized.include?("たばこ") ||
    normalized.include?("吸える") ||
    normalized.include?("喫煙可")

  brandish_words = %w[
    cafe
    caffè
    coffee
    sweets
    bakery
    kitchen
    grill
    diner
    dining
    bistro
    bal
    bar
    lounge
    salon
    wine
    champagne
    listening
    restaurant
    style
    utility
    okiumiya
    jazz
    fooding
    ruelle
    ミエル
    カンジャン
    ケジャン
    ドトール
    勝男
    餃子のかっちゃん
    鉄板神社
    鳥貴族
    磯丸水産
    サンマルク
    スターバックス
    タリーズ
    コメダ
    えん
    ざ
    晩杯屋
    本店
    支店
    号店
    店
    北新地
    大阪駅前第四ビル
  ]

  address_like =
    normalized.match?(/〒|\d{3}-\d{4}|大阪府|大阪市|北区|中央区|浪速区|ビル|b1|b\d|地下/)

  return true if address_like
  return true if brandish_words.any? { |word| normalized.include?(word) } && !explicit_smoking_intent

  return false if explicit_smoking_intent

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

  shop_suffix_like =
    normalized.match?(/(本店|支店|梅田店|大阪駅前|東通店|北新地|堂山|茶屋町|難波店|なんば店)$/)

  return true if shop_suffix_like

  words = normalized.split(/[ 　]/)
  words.size <= 3
end

def detect_query_type(query)
  normalized = query.to_s.downcase

  return "brand_check" if BRAND_LIKE_KEYWORDS.any? { |keyword| normalized.include?(keyword.downcase) }
  return "specific_shop" if unnatural_query?(query)
  return "facility_smoking" if FACILITY_SMOKING_KEYWORDS.any? { |keyword| normalized.include?(keyword.downcase) }
  return "specific_shop" if looks_like_specific_shop_query?(query)

  "general_seo"
end

def general_seo_query?(item)
  item[:query_type].to_s == "general_seo"
end

def article_strategy_target?(item)
  return false unless general_seo_query?(item)
  return false if item[:specific_shop_query]
  return false if item[:query_type].to_s != "general_seo"
  return false if item[:impressions].to_i < 10 && item[:cv_intent].to_s != "high"

  true
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

def ga4_value_score(ga4_data = nil, views: nil, active_users: nil, engagement_seconds: nil, events: nil)
  ga4_data ||= {}

  views = (views || ga4_data[:views]).to_i
  active_users = (active_users || ga4_data[:active_users]).to_i
  engagement_seconds = (engagement_seconds || ga4_data[:engagement_seconds]).to_f
  events = (events || ga4_data[:events]).to_i

  return 0 if views <= 0 && active_users <= 0 && events <= 0

  engagement_score =
    case engagement_seconds
    when 0...10
      0.5
    when 10...30
      1.0
    when 30...90
      1.5
    else
      2.0
    end

  event_score =
    if active_users.positive?
      events.to_f / active_users
    else
      events.to_f
    end

  (
    views.to_f +
    (active_users * 3) +
    (event_score * 5) +
    (engagement_score * 20)
  ).round(1)
end

def theme_multiplier(theme)
  case theme.to_s
  when "デート"
    1.35
  when "シーシャ"
    1.3
  when "個室"
    1.25
  when "バー"
    1.15
  when "居酒屋"
    1.1
  when "喫煙所"
    0.45
  else
    1.0
  end
end

def total_opportunity_score(expected_score:, ga4_score:, theme:)
  (
    expected_score.to_f +
    (ga4_score.to_f * 1.8)
  ) * theme_multiplier(theme)
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

def article_strategy_for(item)
  return "不要" if item[:query_type] != "general_seo"
  return "不要" if item[:specific_shop_query]

  article_relevance_score = item[:article_relevance_score].to_i
  has_strong_article = article_relevance_score >= 70
  has_weak_article = article_relevance_score.positive? && article_relevance_score < 70

  lp_exists =
    item[:landing_page].present?

  high_rank =
    item[:position].to_f <= 15

  low_ctr =
    item[:ctr_percent].to_f < 2.0

  low_articles =
    item[:articles_count].to_i <= 1

  local_area_present =
    item[:local_area].present?

  theme_present =
    item[:theme].present?

  if lp_exists && has_strong_article && high_rank && low_ctr
    return "既存記事改善"
  end

  if local_area_present && !has_strong_article
    return has_weak_article ? "地域特化記事を新規作成" : "地域特化記事を新規作成"
  end

  if theme_present && !has_strong_article && low_articles
    return "テーマ特化記事を新規作成"
  end

  if lp_exists && has_strong_article
    return "既存記事改善"
  end

  "新規記事作成"
end

def strategy_reason_for(item)
  strategy = article_strategy_for(item)

  case strategy
  when "既存記事改善"
    [
      ("順位#{item[:position]}位"),
      ("CTR#{item[:ctr_percent]}%"),
      ("記事関連度#{item[:article_relevance_score]}")
    ].join(" / ")
  when "地域特化記事を新規作成"
    [
      (item[:local_area] || "地域"),
      "専用記事不足",
      ("記事関連度#{item[:article_relevance_score]}")
    ].join(" / ")
  when "テーマ特化記事を新規作成"
    [
      (item[:theme] || "テーマ"),
      "専用記事不足",
      ("記事関連度#{item[:article_relevance_score]}")
    ].join(" / ")
  else
    "専用LP不足"
  end
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

def apply_local_area_keyword(scope, local_area)
  return scope if local_area.blank?

  terms = LOCAL_AREA_KEYWORDS[local_area] || [local_area]

  conditions = []
  binds = {}

  terms.each_with_index do |term, index|
    key = :"local_area_term_#{index}"
    conditions << [
      "name LIKE :#{key}",
      "address LIKE :#{key}",
      "nearest_station LIKE :#{key}"
    ].join(" OR ")
    binds[key] = "%#{term}%"
  end

  scope.where(conditions.map { |condition| "(#{condition})" }.join(" OR "), binds)
end

def shop_count_for(area:, genre:, local_area: nil)
  scope = Shop.approved

  if area.present?
    areas = AREA_DB_ALIASES[area] || [area]
    scope = scope.where(area: areas)
  end

  scope = apply_local_area_keyword(scope, local_area)
  scope = apply_genre_group(scope, genre)
  scope.count
end

def confirmed_shop_count_for(area:, genre:, local_area: nil)
  scope = Shop.approved.where(smoking_unverified: [false, nil])

  if area.present?
    areas = AREA_DB_ALIASES[area] || [area]
    scope = scope.where(area: areas)
  end

  scope = apply_local_area_keyword(scope, local_area)
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

def article_relevance_for(query:, area:, local_area:, genre:, theme:)
  return { count: 0, best_score: 0, best_path: "", best_title: "" } unless defined?(Article)

  query_words =
    query.to_s
         .downcase
         .split(/[ 　]/)
         .map(&:strip)
         .reject(&:blank?)

  candidates = []

  Article.find_each do |article|
    text = [
      article.title,
      article.slug
    ].compact.join(" ").downcase

    score = 0
    score += 35 if local_area.present? && text.include?(local_area.to_s.downcase)
    score += 25 if area.present? && text.include?(area.to_s.downcase)
    score += 25 if genre.present? && text.include?(genre.to_s.downcase)
    score += 20 if theme.present? && text.include?(theme.to_s.downcase)

    query_words.each do |word|
      next if word.length <= 1
      score += 5 if text.include?(word)
    end

    candidates << {
      path: "/articles/#{article.slug}",
      title: article.title.to_s,
      score: score
    } if score.positive?
  end

  best = candidates.max_by { |candidate| candidate[:score] }

  {
    count: candidates.count,
    best_score: best ? best[:score] : 0,
    best_path: best ? best[:path] : "",
    best_title: best ? best[:title] : ""
  }
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

def build_ga4_theme_summary(ga4_pages)
  summary = Hash.new do |hash, key|
    hash[key] = {
      pages: 0,
      views: 0,
      active_users: 0,
      engagement_seconds_total: 0.0,
      events: 0,
      top_pages: []
    }
  end

  ga4_pages.each do |path, data|
    theme = detect_theme(query: nil, landing_page: path)
    next if theme.blank?

    views = data[:views].to_i
    active_users = data[:active_users].to_i
    engagement_seconds = data[:engagement_seconds].to_f
    events = data[:events].to_i

    summary[theme][:pages] += 1
    summary[theme][:views] += views
    summary[theme][:active_users] += active_users
    summary[theme][:engagement_seconds_total] += engagement_seconds
    summary[theme][:events] += events
    summary[theme][:top_pages] << [path, views, engagement_seconds]
  end

  summary.transform_values do |data|
    avg_engagement =
      if data[:pages].positive?
        data[:engagement_seconds_total] / data[:pages]
      else
        0
      end

    data.merge(
      avg_engagement_seconds: avg_engagement.round(1),
      ga4_score: ga4_value_score(
        views: data[:views],
        active_users: data[:active_users],
        engagement_seconds: avg_engagement,
        events: data[:events]
      ),
      top_pages: data[:top_pages].sort_by { |_, views, _| -views }.first(5)
    )
  end
end

def infer_landing_page(query:, area:, local_area:, genre:, theme:)
  candidates = []

  relevance =
    article_relevance_for(
      query: query,
      area: area,
      local_area: local_area,
      genre: genre,
      theme: theme
    )

  if relevance[:best_path].present?
    candidates << [relevance[:best_path], relevance[:best_score]]
  end

  if area == "梅田"
    candidates << ["/umeda", 2]
    candidates << ["/umeda/genre/bar", 4] if genre == "バー"
    candidates << ["/umeda/genre/izakaya", 4] if genre == "居酒屋"
  elsif area == "難波"
    candidates << ["/namba", 2]
  elsif area == "西中島"
    candidates << ["/nishinakajima", 2]
  elsif area == "本町"
    candidates << ["/honmachi", 2]
  end

  candidates.max_by { |_, score| score }&.first.to_s
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

  strategy = item[:strategy]

  if strategy == "既存記事改善"
    lines << "既存LPを改善する: #{item[:landing_page]}"
    lines << "title/meta/冒頭を検索意図に寄せる"
    lines << "関連記事リンクと店舗カード導線を強化する"
  elsif strategy == "地域特化記事を新規作成"
    lines << "#{item[:local_area]}特化記事を新規作成する"
  elsif strategy == "テーマ特化記事を新規作成"
    lines << "#{item[:theme]}特化記事を新規作成する"
  end

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
      puts "   対象: #{item[:area] || '未判定'} / #{item[:local_area] || '広域'} / #{item[:genre] || '未判定'} / CV意図: #{item[:cv_intent]}"
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

def print_ga4_theme_summary(title, theme_summary, limit: 10)
  puts
  puts "=============================="
  puts title
  puts "=============================="

  theme_summary
    .sort_by { |theme, data| [-data[:ga4_score].to_f, theme.to_s] }
    .first(limit)
    .each_with_index do |(theme, data), index|
      puts
      puts "#{index + 1}. #{theme}"
      puts "   GA4価値: #{data[:ga4_score]} / PV: #{data[:views]} / Active: #{data[:active_users]} / 平均滞在: #{data[:avg_engagement_seconds]}秒 / Events: #{data[:events]} / 対象ページ: #{data[:pages]}"

      if data[:top_pages].any?
        puts "   主要ページ:"
        data[:top_pages].each do |path, views, engagement_seconds|
          puts "   - #{path} / PV#{views} / 滞在#{engagement_seconds.to_f.round(1)}秒"
        end
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
    puts "   area: #{item[:area] || '未判定'} / local_area: #{item[:local_area] || '広域'} / genre: #{item[:genre] || '未判定'} / theme: #{item[:theme] || '未判定'} / CV意図: #{item[:cv_intent]}"
    puts "   DB集計ジャンル: #{item[:genre].present? ? (GENRE_DB_GROUPS[item[:genre]] || [item[:genre]]).join(' / ') : '未判定'}"
    puts "   DB店舗: #{item[:shops_count]} / 確認済み: #{item[:confirmed_count]} / 記事数: #{item[:articles_count]} / 記事関連度: #{item[:article_relevance_score]}"
    puts "   関連記事候補: #{item[:article_relevance_path].presence || 'なし'}"

    if item[:landing_page].present?
      lp_label = item[:inferred_landing_page] ? "推定LP" : "LP"
      puts "   #{lp_label}: #{item[:landing_page]} / LP表示: #{item[:lp_impressions]} / LPクリック: #{item[:lp_clicks]} / LP CTR: #{item[:lp_ctr_percent]}% / LP順位: #{item[:lp_position]}"
    else
      puts "   LP: 未取得"
    end

    puts "   GA4: PV#{item[:ga4_views]} / Active#{item[:ga4_active_users]} / 滞在#{item[:ga4_engagement_seconds]}秒 / ページGA4価値#{item[:page_ga4_score]} / テーマGA4価値#{item[:theme_ga4_score]} / GA4価値#{item[:ga4_score]}"
    puts "   期待値: #{item[:expected_score]} / 総合: #{item[:total_score]} / ROI: #{item[:roi_score]} / 推奨施策: #{item[:recommended_action]}"
    puts "   作業コスト: #{item[:work_label]}"
    puts "   記事戦略: #{item[:strategy]} (#{item[:strategy_reason]})"
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
      "local_area",
      "genre",
      "cv_intent",
      "query_type",
      "theme",
      "recommended_action",
      "expected_score",
      "ga4_score",
      "page_ga4_score",
      "theme_ga4_score",
      "total_score",
      "roi_score",
      "work_label",
      "strategy",
      "strategy_reason",
      "impressions",
      "clicks",
      "ctr_percent",
      "position",
      "landing_page",
      "inferred_landing_page",
      "shops_count",
      "confirmed_count",
      "articles_count",
      "article_relevance_count",
      "article_relevance_score",
      "article_relevance_path",
      "article_relevance_title",
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
          item[:local_area],
          item[:genre],
          item[:cv_intent],
          item[:query_type],
          item[:theme],
          item[:recommended_action],
          item[:expected_score],
          item[:ga4_score],
          item[:page_ga4_score],
          item[:theme_ga4_score],
          item[:total_score],
          item[:roi_score],
          item[:work_label],
          item[:strategy],
          item[:strategy_reason],
          item[:impressions],
          item[:clicks],
          item[:ctr_percent],
          item[:position],
          item[:landing_page],
          item[:inferred_landing_page],
          item[:shops_count],
          item[:confirmed_count],
          item[:articles_count],
          item[:article_relevance_count],
          item[:article_relevance_score],
          item[:article_relevance_path],
          item[:article_relevance_title],
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
ga4_theme_summary = build_ga4_theme_summary(ga4_pages)
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
  local_area = detect_local_area(query)
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

  shops_count = shop_count_for(area: area, genre: genre, local_area: local_area)
  confirmed_count = confirmed_shop_count_for(area: area, genre: genre, local_area: local_area)
  articles_count = article_count_for(area: area, genre: genre)

  article_relevance =
    article_relevance_for(
      query: query,
      area: area,
      local_area: local_area,
      genre: genre,
      theme: detect_theme(query: query, landing_page: nil)
    )

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

  theme = detect_theme(query: query, landing_page: landing_page)

  if landing_page.blank?
    landing_page =
      infer_landing_page(
        query: query,
        area: area,
        local_area: local_area,
        genre: genre,
        theme: theme
      )
  end

  theme = detect_theme(query: query, landing_page: landing_page)
  ga4_data = ga4_pages[landing_page] || {}
  page_ga4_score = ga4_value_score(ga4_data)
  theme_ga4_score = theme.present? ? ga4_theme_summary.dig(theme, :ga4_score).to_f : 0.0
  ga4_score = [page_ga4_score, theme_ga4_score].max

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

  total_score =
    total_opportunity_score(
      expected_score: expected_score,
      ga4_score: ga4_score,
      theme: theme
    ).round(1)

  work_cost = work_cost_for(recommended_action)
  roi_score = roi_score_for(expected_score: total_score, action: recommended_action)
  work_label = work_label_for(recommended_action)

  strategy = article_strategy_for(
    {
      query_type: query_type,
      specific_shop_query: specific_shop_query,
      landing_page: landing_page,
      position: position,
      ctr_percent: ctr_percent,
      articles_count: articles_count,
      article_relevance_score: article_relevance[:best_score],
      local_area: local_area,
      theme: theme
    }
  )

  strategy_reason = strategy_reason_for(
    {
      query_type: query_type,
      specific_shop_query: specific_shop_query,
      landing_page: landing_page,
      position: position,
      ctr_percent: ctr_percent,
      articles_count: articles_count,
      article_relevance_score: article_relevance[:best_score],
      local_area: local_area,
      theme: theme
    }
  )

  {
    query: query,
    area: area,
    local_area: local_area,
    genre: genre,
    cv_intent: cv_intent,
    query_type: query_type,
    theme: theme,
    ga4_score: ga4_score,
    page_ga4_score: page_ga4_score,
    theme_ga4_score: theme_ga4_score,
    total_score: total_score,
    specific_shop_query: specific_shop_query,
    clicks: clicks.to_i,
    impressions: impressions.to_i,
    ctr_percent: ctr_percent.round(2),
    position: position.round(1),
    shops_count: shops_count,
    confirmed_count: confirmed_count,
    articles_count: articles_count,
    article_relevance_count: article_relevance[:count],
    article_relevance_score: article_relevance[:best_score],
    article_relevance_path: article_relevance[:best_path],
    article_relevance_title: article_relevance[:best_title],
    pv_score: pv_score.round(1),
    revenue_score: revenue_score.round(1),
    db_gap_score: db_gap_score.round(1),
    ctr_score: ctr_score.round(1),
    expected_score: expected_score,
    recommended_action: recommended_action,
    work_cost: work_cost,
    roi_score: roi_score,
    work_label: work_label,
    strategy: strategy,
    strategy_reason: strategy_reason,
    landing_page: landing_page,
    inferred_landing_page: lp_data[:page].to_s.blank? && landing_page.present?,
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
puts "GA4テーマ数: #{ga4_theme_summary.size}"

puts
puts "エリア別DB件数"

AREA_DB_ALIASES.each do |area, aliases|
  count = Shop.approved.where(area: aliases).count
  puts "- #{area}: #{count}件"
end

general_seo_items = items.select { |item| general_seo_query?(item) }

print_section("総合判断：GA4×GSCで次にやるべき施策", general_seo_items, :total_score)
print_section("一般検索：本当に伸ばすべきSEO", general_seo_items, :revenue_score)
print_section("PV最大化：流入を増やすなら優先", items, :pv_score)
print_section("収益最大化：送客・予約につなげるなら優先", items, :revenue_score)
print_section("DB強化：検索需要に対して店舗DBが弱い候補", items, :db_gap_score)
print_section("CTR改善：表示はあるのにクリックを取り切れていない候補", items, :ctr_score)

print_section("最優先施策：期待値が高い順", items, :expected_score)

print_todo_section("自動TODO：ROIが高い順", items)

print_section(
  "既存改善優先：順位が見えていてCTR改善余地が高い",
  items.select { |item| item[:strategy] == "既存記事改善" },
  :total_score,
  general_only: false
)

print_section(
  "新規記事優先：専用記事不足",
  items.select { |item| article_strategy_target?(item) && item[:strategy] != "既存記事改善" && item[:strategy] != "不要" },
  :total_score,
  general_only: false
)

print_section("店舗名系：個別店舗ページ・記事で拾えている検索", items.select { |item| item[:query_type] == "specific_shop" }, :pv_score, general_only: false)
print_section("確認検索っぽいブランド系：優先順位から分離", items.select { |item| item[:query_type] == "brand_check" }, :pv_score, general_only: false)
print_section("喫煙所系：飲食送客SEOとは分離", items.select { |item| item[:query_type] == "facility_smoking" }, :pv_score, general_only: false)

print_ga4_theme_summary("GA4テーマ分析：読まれているテーマ", ga4_theme_summary)
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