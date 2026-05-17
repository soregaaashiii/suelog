# /Users/kawamuratakuya/dev/suelog/app/models/shop.rb
# frozen_string_literal: true

class Shop < ApplicationRecord
  # ===== Associations =====
  has_many :reviews, dependent: :destroy
  has_many :shop_edit_requests, dependent: :destroy
  has_many :shop_reports, dependent: :destroy
  has_many :shop_clicks, dependent: :destroy

  # ===== ActiveStorage =====
  has_many_attached :food_photos
  has_many_attached :interior_photos
  has_many_attached :exterior_photos
  has_many_attached :menu_photos

  # ===== Genre master =====
  GENRES = [
    "アメリカ料理",
    "居酒屋",
    "イタリアン",
    "インド料理",
    "うどん",
    "エスニック料理",
    "オイスターバー",
    "お好み焼き",
    "カフェ",
    "カラオケ",
    "カレー",
    "韓国料理",
    "牛肉料理",
    "串カツ",
    "串揚げ",
    "創作料理",
    "しゃぶしゃぶ",
    "ジビエ",
    "シーシャ",
    "ステーキ",
    "スナック",
    "スポーツバー",
    "スパニッシュ",
    "そば",
    "ダイニングバー",
    "たこ焼き",
    "中華",
    "天ぷら",
    "鉄板焼き",
    "豚肉料理",
    "鶏肉料理",
    "バー",
    "バル",
    "ハブ",
    "パブ",
    "ビアガーデン",
    "ビストロ",
    "フレンチ",
    "ホルモン",
    "もつ鍋",
    "メキシコ料理",
    "ラーメン",
    "ラウンジ",
    "レストラン",
    "ワインバー",
    "和食",
    "海鮮",
    "餃子",
    "焼鳥",
    "焼肉",
    "洋食",
    "立ち飲み",
    "寿司",
    "喫茶店",
    "その他"
  ].freeze

  GENRE_ALIASES = {
    "カフェ・喫茶" => "カフェ",
    "カフェバー" => "カフェ",
    "喫茶店 / カフェ" => "カフェ",
    "居酒屋・ダイニングバー" => "ダイニングバー",
    "焼き鳥" => "焼鳥",
    "串かつ" => "串カツ",
    "串あげ" => "串揚げ",
    "鶏料理" => "鶏肉料理",
    "チキン料理" => "鶏肉料理",
    "豚肉" => "豚肉料理",
    "鶏肉" => "鶏肉料理",
    "牛肉" => "牛肉料理",
    "バー / パブ" => "バー",
    "スペイン料理" => "スパニッシュ"
  }.freeze

  GENRE_SEARCH_EXPANSIONS = {
    "カフェ" => ["カフェ", "カフェ・喫茶", "喫茶店 / カフェ", "カフェバー"],
    "喫茶店" => ["喫茶店"],
    "バー" => ["バー", "バー / パブ"],
    "パブ" => ["パブ"],
    "ハブ" => ["ハブ"],
    "ラウンジ" => ["ラウンジ"],
    "焼鳥" => ["焼鳥", "焼き鳥"],
    "鶏肉料理" => ["鶏肉料理", "鶏料理", "チキン料理", "鶏肉"],
    "豚肉料理" => ["豚肉料理", "豚肉"],
    "牛肉料理" => ["牛肉料理", "牛肉"],
    "串カツ" => ["串カツ", "串かつ"],
    "串揚げ" => ["串揚げ", "串あげ"],
    "スパニッシュ" => ["スパニッシュ", "スペイン料理"]
  }.freeze

  AREAS = [
    "阿倍野", "阿倍野橋", "旭区清水", "朝潮橋", "淡路", "石橋阪大前", "泉大津", "泉ヶ丘", "泉佐野", "和泉中央",
    "今里", "茨木", "茨木市", "梅田", "江坂", "難波", "大阪阿部野橋", "大阪上本町", "大阪狭山市", "大阪天満宮",
    "大日", "大東市", "大正", "岡町", "貝塚", "香里園", "柏原", "門真市", "岸和田", "京橋", "喜連瓜破", "九条",
    "河内小阪", "河内国分", "河内長野", "河内松原", "岸辺", "北新地", "北千里", "北花田", "布施", "堺", "堺東",
    "桜川", "新金岡", "新今宮", "新大阪", "心斎橋", "住道", "千里中央", "千林大宮", "高槻", "高槻市", "玉造",
    "天下茶屋", "天王寺", "天満橋", "豊中", "中百舌鳥", "長居", "西梅田", "西九条", "野田", "東岸和田", "東三国",
    "東梅田", "東大阪市", "東花園", "枚方市", "平野", "深井", "藤井寺", "古市", "弁天町", "本町", "松原", "箕面",
    "都島", "守口市", "八尾", "山田", "淀屋橋", "四ツ橋"
  ].freeze

  AREA_AUTO_RULES = {
    "梅田" => [
      "梅田",
      "大阪駅",
      "梅田駅",
      "東梅田",
      "東梅田駅",
      "西梅田",
      "西梅田駅",
      "北新地",
      "北新地駅",
      "中崎町",
      "中崎町駅",
      "中津",
      "中津駅",
      "福島",
      "福島駅"
    ],
    "難波" => [
      "難波",
      "なんば",
      "難波駅",
      "なんば駅",
      "jr難波",
      "jr難波駅",
      "大阪難波",
      "大阪難波駅",
      "心斎橋",
      "心斎橋駅",
      "日本橋",
      "日本橋駅",
      "大国町",
      "大国町駅",
      "桜川",
      "桜川駅"
    ]
  }.freeze

  # ===== Smoking status =====
  enum :smoking_area, {
    separated: 0,
    all_smoking: 1,
    unknown: 2
  }, prefix: true

  enum :smoking_type, {
    both_ok: 0,
    electronic_only: 1,
    paper_only: 2,
    unknown: 3
  }, prefix: true

  # ===== Scopes =====
  scope :approved, -> { where(approved: true, on_hold: false) }
  scope :on_hold_only, -> { where(on_hold: true) }
  scope :excluding_shop, ->(shop) { where.not(id: shop.id) }

  scope :keyword, lambda { |q|
    kw = q.to_s.strip.downcase
    next all if kw.blank?

    like = "%#{sanitize_sql_like(kw)}%"
    where(
      <<~SQL.squish,
        LOWER(COALESCE(shops.name, '')) LIKE :like
        OR LOWER(COALESCE(shops.address, '')) LIKE :like
        OR LOWER(COALESCE(shops.area, '')) LIKE :like
        OR LOWER(COALESCE(shops.nearest_station, '')) LIKE :like
        OR LOWER(COALESCE(shops.phone, '')) LIKE :like
        OR LOWER(COALESCE(shops.public_store_details, '')) LIKE :like
        OR LOWER(COALESCE(shops.genre, '')) LIKE :like
        OR LOWER(COALESCE(shops.genre_other, '')) LIKE :like
        OR LOWER(COALESCE(shops.opening_hours_text, '')) LIKE :like
        OR LOWER(COALESCE(shops.holiday_hours_text, '')) LIKE :like
        OR LOWER(COALESCE(shops.closed_days_text, '')) LIKE :like
      SQL
      like: like
    )
  }

  scope :text_like, lambda { |column, value|
    v = value.to_s.strip
    next all if v.blank?

    like = "%#{sanitize_sql_like(v)}%"
    where("shops.#{column} LIKE ?", like)
  }

  scope :genre_like, lambda { |value|
    terms = genre_search_terms(value)
    next all if terms.blank?

    conditions = []
    bind_values = {}

    terms.each_with_index do |term, idx|
      key = :"like_#{idx}"
      conditions << "(shops.genre LIKE :#{key} OR shops.genre_other LIKE :#{key})"
      bind_values[key] = "%#{sanitize_sql_like(term)}%"
    end

    where(conditions.join(" OR "), bind_values)
  }

  # ===== Validations =====
  validates :name, :address, :last_confirmed_on, presence: { message: "を入力してください" }
  validates :genre, presence: { message: "を選択してください" }

  validates :smoking_area, presence: { message: "を選択してください" }, if: :approved?
  validates :smoking_type, presence: { message: "を選択してください" }, if: :approved?

  validates :tabelog_url,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "は正しいURLを入力してください" },
            allow_blank: true

  validates :hotpepper_url,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "は正しいURLを入力してください" },
            allow_blank: true

  validates :custom_affiliate_url,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "は正しいURLを入力してください" },
            allow_blank: true

  validates :custom_affiliate_label,
            length: { maximum: 50 },
            allow_blank: true

  validate :last_confirmed_on_cannot_be_future

  # 電話番号の重複防止（digitsのみ）
  before_validation :set_normalized_phone
  before_validation :normalize_genre_value
  before_validation :normalize_opening_hours_json
  before_validation :assign_area_from_location_if_blank
  before_validation :set_default_smoking_values

  # 電話番号重複は系列店・同一受付番号の可能性があるため保存は止めない。
  # 重複警告は duplicate_flag_present? / duplicate_candidates で表示する。

  # ジャンル正規化
  # opening_hours_json は既存データ互換のため残す

  # ===== Geocoding =====
  def geocode_address
    [address, area]
      .compact
      .map(&:to_s)
      .map { |v| v.gsub(/\s+/, " ").strip }
      .reject(&:blank?)
      .join(" ")
  end

  geocoded_by :geocode_address, latitude: :latitude, longitude: :longitude
  after_validation :safe_geocode, if: :should_geocode?

  def safe_geocode
    geocode
  rescue Geocoder::Error => e
    Rails.logger.warn("[geocode skipped] #{e.class}: #{e.message}")
    self.latitude = nil if latitude_changed?
    self.longitude = nil if longitude_changed?
    true
  end

  def ensure_geocoded!
    return false if geocode_address.blank?
    return false unless geocoding_enabled?

    geocode

    if latitude.present? && longitude.present?
      save!(validate: false)
      true
    else
      false
    end
  rescue Geocoder::Error => e
    Rails.logger.warn("[ensure_geocoded!] #{e.class}: #{e.message}")
    false
  end

  # ===== Class helpers =====
  def self.genre_options
    GENRES
  end

  def self.genre_search_terms(value)
    v = value.to_s.strip
    return [] if v.blank?

    normalized = GENRE_ALIASES[v] || v
    ([normalized] + Array(GENRE_SEARCH_EXPANSIONS[normalized])).map { |term| term.to_s.strip }.reject(&:blank?).uniq
  end

  def self.normalize_duplicate_text(text)
    return "" if text.blank?

    text.to_s
        .tr("０-９Ａ-Ｚａ-ｚ", "0-9A-Za-z")
        .downcase
        .gsub(/[[:space:]]+/, "")
        .gsub(/[()（）\[\]【】「」『』・･,，.。\-ー−―]/, "")
        .strip
  end

  def self.duplicate_exists_for_import?(attrs, exclude_id: nil)
    phone = attrs[:phone].to_s.gsub(/[^0-9]/, "")
    name = attrs[:name].to_s.strip
    address = attrs[:address].to_s.strip

    scope = exclude_id.present? ? Shop.where.not(id: exclude_id) : Shop.all

    # ① 電話番号だけの一致では登録不可にしない
    # 系列店・同一受付番号の別店舗があるため、電話番号一致は警告表示に留める。

    # ② 名前・住所で判定
    return true if name.present? && scope.where(name: name).exists?
    return true if address.present? && scope.where(address: address).exists?

    normalized_name = normalize_duplicate_text(name)
    normalized_address = normalize_duplicate_text(address)

    scope.limit(5000).pluck(:name, :address).any? do |n, a|
      cn = normalize_duplicate_text(n)
      ca = normalize_duplicate_text(a)

      name_match =
        normalized_name.present? &&
        cn.present? &&
        normalized_name == cn

      address_match =
        normalized_address.present? &&
        ca.present? &&
        (
          normalized_address == ca ||
          normalized_address.include?(ca) ||
          ca.include?(normalized_address)
        )

      name_match || address_match
    end
  end

  # ===== Display helpers =====
  def display_genre
    return "" if genre.blank?

    genre == "その他" ? genre_other.to_s : genre.to_s
  end

  def smoking_area_label
    case smoking_area
    when "all_smoking"
      "席で喫煙可"
    when "separated"
      "喫煙所あり"
    when "unknown"
      "不明"
    else
      "未設定"
    end
  end

  def smoking_type_label
    case smoking_type
    when "both_ok"
      "紙・加熱式どちらもOK"
    when "electronic_only"
      "加熱式タバコのみOK"
    when "paper_only"
      "紙タバコのみOK"
    when "unknown"
      "不明"
    else
      "未設定"
    end
  end

  def hold_reason_label
    case hold_reason.to_s
    when "closed"
      "営業終了"
    when "relocated"
      "移転"
    when "temporarily_closed"
      "休業"
    when "was_non_smoking"
      "禁煙店だった"
    when "became_non_smoking"
      "禁煙店になった"
    else
      "保留"
    end
  end

  # =========================
  # サムネイル（安全版）
  # =========================
  def thumbnail_attachment
    kind = (respond_to?(:thumbnail_kind) ? thumbnail_kind.to_s : "").presence || "auto"
    idx = (respond_to?(:thumbnail_index) ? thumbnail_index.to_i : 1)
    idx = 1 if idx <= 0

    attachments =
      case kind
      when "food"
        safe_attachments(food_photos)
      when "interior"
        safe_attachments(interior_photos)
      when "exterior"
        safe_attachments(exterior_photos)
      when "menu"
        safe_attachments(menu_photos)
      else
        auto_thumbnail_attachments
      end

    pick_attachment_from(attachments, idx)
  rescue StandardError => e
    Rails.logger.warn("[thumbnail_attachment] #{e.class}: #{e.message}")
    nil
  end

  # =========================
  # 営業時間（簡易テキスト表示）
  # =========================
  def display_opening_hours_text
    opening_hours_text.presence || derived_opening_hours_text.presence || "未設定"
  end

  def display_holiday_hours_text
    holiday_hours_text.presence || "未設定"
  end

  def display_closed_days_text
    closed_days_text.presence || derived_closed_days_text.presence || "未設定"
  end

  # =========================
  # 既存の構造化JSON互換
  # =========================
  def opening_hours_data
    (opening_hours_json.presence || {}).to_h
  end

  def open_now?
    now = Time.zone.now
    now_min = now.hour * 60 + now.min

    if holiday_today?
      holiday_ranges = time_ranges_from_text(holiday_hours_text)
      return holiday_ranges.any? { |open_min, close_min| within_range?(now_min, open_min, close_min) } if holiday_ranges.present?
    end

    today = opening_hours_data[today_key]

    if today.present?
      return false if truthy?(today["closed"])

      open_min = hhmm_to_min(today["open"])
      close_min = hhmm_to_min(today["close"])
      return false if open_min.nil? || close_min.nil?

      if truthy?(today["break_enabled"])
        bs = hhmm_to_min(today["break_start"])
        be = hhmm_to_min(today["break_end"])
        return false if bs && be && within_range?(now_min, bs, be)
      end

      return within_range?(now_min, open_min, close_min)
    end

    weekday_ranges = time_ranges_from_text(opening_hours_text, weekday_label_for_today)
    weekday_ranges.any? { |open_min, close_min| within_range?(now_min, open_min, close_min) }
  end

  def today_closing_time
    now = Time.zone.now
    now_min = now.hour * 60 + now.min

    ranges =
      if holiday_today? && time_ranges_from_text(holiday_hours_text).present?
        time_ranges_from_text(holiday_hours_text)
      elsif opening_hours_data[today_key].present?
        today = opening_hours_data[today_key]
        return nil if truthy?(today["closed"])

        open_min = hhmm_to_min(today["open"])
        close_min = hhmm_to_min(today["close"])
        open_min.present? && close_min.present? ? [[open_min, close_min]] : []
      else
        time_ranges_from_text(opening_hours_text, weekday_label_for_today)
      end

    current_range = ranges.find { |open_min, close_min| within_range?(now_min, open_min, close_min) }
    return nil if current_range.blank?

    _open_min, close_min = current_range

    closing_date = Time.zone.today

    if close_min <= now_min
      closing_date += 1.day
    end

    hour = close_min / 60
    min = close_min % 60

    if hour >= 24
      closing_date += (hour / 24).days
      hour = hour % 24
    end

    Time.zone.local(closing_date.year, closing_date.month, closing_date.day, hour, min)
  end

  def opening_hours_lines
    order = [
      ["月", "monday"],
      ["火", "tuesday"],
      ["水", "wednesday"],
      ["木", "thursday"],
      ["金", "friday"],
      ["土", "saturday"],
      ["日", "sunday"]
    ]

    data = opening_hours_data

    order.map do |label, key|
      d = data[key]

      if d.blank?
        [label, "未設定"]
      elsif truthy?(d["closed"])
        [label, "休み"]
      else
        base = "#{d["open"]}-#{d["close"]}"
        if truthy?(d["break_enabled"]) && d["break_start"].present? && d["break_end"].present?
          [label, "#{base}（休憩 #{d["break_start"]}-#{d["break_end"]}）"]
        else
          [label, base]
        end
      end
    end
  end

  # =========================
  # 一覧用軽量重複フラグ
  # =========================
  def duplicate_flag_present?
    duplicate_flag_state != :none
  end

  def duplicate_flag_state
    scope = Shop.where.not(id: id)

    if place_id_column_available? && place_id_value.present?
      matched = scope.where(place_id: place_id_value)
      return duplicate_scope_state(matched) if matched.exists?
    end

    if normalized_phone.present?
      matched = scope.where(normalized_phone: normalized_phone)
      return duplicate_scope_state(matched) if matched.exists?
    end

    if name.present?
      matched = scope.where(name: name)
      return duplicate_scope_state(matched) if matched.exists?
    end

    if address.present?
      matched = scope.where(address: address)
      return duplicate_scope_state(matched) if matched.exists?
    end

    normalized_name = self.class.normalize_duplicate_text(name)
    normalized_address = self.class.normalize_duplicate_text(address)

    return :none if normalized_name.blank? && normalized_address.blank?

    matched_ids = []

    scope.order(created_at: :desc).limit(5000).pluck(:id, :name, :address).each do |candidate_id, candidate_name, candidate_address|
      c_name = self.class.normalize_duplicate_text(candidate_name)
      c_address = self.class.normalize_duplicate_text(candidate_address)

      name_match =
        normalized_name.present? &&
        c_name.present? &&
        normalized_name == c_name

      address_match =
        normalized_address.present? &&
        c_address.present? &&
        (
          normalized_address == c_address ||
          normalized_address.include?(c_address) ||
          c_address.include?(normalized_address)
        )

      matched_ids << candidate_id if name_match || address_match
    end

    return :none if matched_ids.blank?

    duplicate_scope_state(Shop.where(id: matched_ids))
  rescue StandardError => e
    Rails.logger.warn("[duplicate_flag_state] #{e.class}: #{e.message}")
    :none
  end

  # =========================
  # 重複候補
  # =========================
  def duplicate_candidates(limit: 10)
    ids = []
    base_scope = Shop.excluding_shop(self)

    if place_id_column_available? && place_id_value.present?
      ids.concat(
        base_scope
          .where(place_id: place_id_value)
          .order(created_at: :desc)
          .limit(limit)
          .pluck(:id)
      )
    end

    if normalized_phone.present?
      ids.concat(
        base_scope
          .where(normalized_phone: normalized_phone)
          .order(created_at: :desc)
          .limit(limit * 3)
          .pluck(:id)
      )
    end

    if name.present?
      ids.concat(
        base_scope
          .where(name: name)
          .order(created_at: :desc)
          .limit(limit * 5)
          .pluck(:id)
      )
    end

    if address.present?
      ids.concat(
        base_scope
          .where(address: address)
          .order(created_at: :desc)
          .limit(limit * 5)
          .pluck(:id)
      )
    end

    normalized_name = self.class.normalize_duplicate_text(name)
    normalized_address = self.class.normalize_duplicate_text(address)

    if normalized_name.present? || normalized_address.present?
      base_scope.order(created_at: :desc).limit(5000).to_a.each do |candidate|
        next if candidate.id == id

        candidate_name = self.class.normalize_duplicate_text(candidate.name)
        candidate_address = self.class.normalize_duplicate_text(candidate.address)

        name_match =
          normalized_name.present? &&
          candidate_name.present? &&
          normalized_name == candidate_name

        address_match =
          normalized_address.present? &&
          candidate_address.present? &&
          (
            normalized_address == candidate_address ||
            normalized_address.include?(candidate_address) ||
            candidate_address.include?(normalized_address)
          )

        ids << candidate.id if name_match || address_match
      end
    end

    ids = ids.compact.uniq.first(limit * 3)
    return [] if ids.blank?

    candidates = Shop.where(id: ids).index_by(&:id)

    ids.map do |candidate_id|
      candidate = candidates[candidate_id]
      next unless candidate

      {
        shop: candidate,
        score: duplicate_score_against(candidate),
        reasons: duplicate_reasons_against(candidate)
      }
    end
       .compact
       .sort_by { |row| -row[:score] }
       .first(limit)
  rescue StandardError => e
    Rails.logger.warn("[duplicate_candidates] #{e.class}: #{e.message}")
    []
  end

  def duplicate_score_against(other)
    score = 0

    if place_id_column_available? &&
       other.respond_to?(:place_id) &&
       place_id_value.present? &&
       other.place_id.present? &&
       place_id_value == other.place_id
      score += 100
    end

    if other.respond_to?(:normalized_phone) &&
       normalized_phone.present? &&
       other.normalized_phone.present? &&
       normalized_phone == other.normalized_phone
      score += 60
    end

    score += 40 if name.present? && other.name.present? && name == other.name
    score += 40 if address.present? && other.address.present? && address == other.address

    my_name = self.class.normalize_duplicate_text(name)
    other_name = self.class.normalize_duplicate_text(other.name)
    score += 30 if my_name.present? && other_name.present? && my_name == other_name

    my_address = self.class.normalize_duplicate_text(address)
    other_address = self.class.normalize_duplicate_text(other.address)
    if my_address.present? && other_address.present?
      if my_address == other_address
        score += 30
      elsif my_address.include?(other_address) || other_address.include?(my_address)
        score += 15
      end
    end

    if other.approved?
      score += 5
    elsif other.respond_to?(:rejected?) && other.rejected?
      score += 1
    end

    score
  rescue StandardError => e
    Rails.logger.warn("[duplicate_score_against] #{e.class}: #{e.message}")
    0
  end

  def duplicate_reasons_against(other)
    reasons = []

    if place_id_column_available? &&
       other.respond_to?(:place_id) &&
       place_id_value.present? &&
       other.place_id.present? &&
       place_id_value == other.place_id
      reasons << "place_id一致"
    end

    if other.respond_to?(:normalized_phone) &&
       normalized_phone.present? &&
       other.normalized_phone.present? &&
       normalized_phone == other.normalized_phone
      reasons << "電話番号一致"
    end

    reasons << "店名完全一致" if name.present? && other.name.present? && name == other.name
    reasons << "住所完全一致" if address.present? && other.address.present? && address == other.address

    my_name = self.class.normalize_duplicate_text(name)
    other_name = self.class.normalize_duplicate_text(other.name)
    reasons << "店名一致" if my_name.present? && other_name.present? && my_name == other_name

    my_address = self.class.normalize_duplicate_text(address)
    other_address = self.class.normalize_duplicate_text(other.address)
    if my_address.present? && other_address.present?
      if my_address == other_address
        reasons << "住所一致"
      elsif my_address.include?(other_address) || other_address.include?(my_address)
        reasons << "住所近似"
      end
    end

    reasons << duplicate_status_label(other)
    reasons.uniq
  rescue StandardError => e
    Rails.logger.warn("[duplicate_reasons_against] #{e.class}: #{e.message}")
    []
  end

  def freshness_score
    score = 0

    if last_confirmed_on.present?
      days = (Date.current - last_confirmed_on).to_i

      score +=
        if days <= 30
          60
        elsif days <= 90
          45
        elsif days <= 180
          30
        elsif days <= 365
          15
        else
          5
        end
    end

    score += 20 if approved?
    score += 10 if respond_to?(:tabelog_affiliate_url) && tabelog_affiliate_url.present?
    score += 10 if updated_at.present? && updated_at >= 30.days.ago

    score -= 25 if respond_to?(:smoking_unverified) && smoking_unverified?
    score -= 10 if smoking_area.to_s == "unknown"
    score -= 10 if smoking_type.to_s == "unknown"

    [[score, 0].max, 100].min
  rescue StandardError => e
    Rails.logger.warn("[freshness_score] #{e.class}: #{e.message}")
    0
  end

  def freshness_label
    case freshness_score
    when 80..100
      "鮮度：高"
    when 50...80
      "鮮度：中"
    when 1...50
      "鮮度：低"
    else
      "鮮度：未確認"
    end
  end

  def freshness_level
    case freshness_score
    when 80..100
      "high"
    when 50...80
      "middle"
    when 1...50
      "low"
    else
      "unknown"
    end
  end

  private

  def assign_area_from_location_if_blank
    return if area.present?

    inferred = infer_area_from_location
    self.area = inferred if inferred.present?
  end

  def infer_area_from_location
    station_text = normalize_area_match_text(nearest_station)
    address_text = normalize_area_match_text(address)

    AREA_AUTO_RULES.each do |area_name, keywords|
      return area_name if keywords.any? { |keyword| station_text.include?(normalize_area_match_text(keyword)) }
    end

    AREA_AUTO_RULES.each do |area_name, keywords|
      return area_name if keywords.any? { |keyword| address_text.include?(normalize_area_match_text(keyword)) }
    end

    nil
  end

  def normalize_area_match_text(text)
    text.to_s
        .unicode_normalize(:nfkc)
        .downcase
        .gsub(/[[:space:]]+/, "")
  end

  def normalize_genre_value
    self.genre = genre.to_s.strip
    self.genre_other = genre_other.to_s.strip if respond_to?(:genre_other)

    self.genre = GENRE_ALIASES[genre] || genre

    return if genre.blank?
    return if GENRES.include?(genre)

    if respond_to?(:genre_other)
      self.genre_other = genre if genre_other.blank?
    end

    self.genre = "その他"
  end

  def normalize_opening_hours_json
    return unless respond_to?(:opening_hours_json)

    self.opening_hours_json = OpeningHoursParser.normalize_json(opening_hours_json)
  end

  def derived_opening_hours_text
    rows = opening_hours_lines.reject { |_label, value| value == "未設定" || value == "休み" }
    return nil if rows.blank?

    rows.map { |label, value| "#{label} #{value}" }.join(" / ")
  end

  def derived_closed_days_text
    rows = opening_hours_lines.select { |_label, value| value == "休み" }
    return nil if rows.blank?

    rows.map(&:first).join("・")
  end
  def holiday_today?
    today = Time.zone.today

    # ひとまず祝日営業時間が入っている日は、祝日用の時間も候補として見る。
    # 祝日判定ライブラリを入れていないため、通常営業時間が読めない問題の回避を優先する。
    today.saturday? || today.sunday? || holiday_hours_text.present?
  end

  def weekday_label_for_today
    %w[日 月 火 水 木 金 土][Time.zone.today.wday]
  end

  def time_ranges_from_text(text, target_label = nil)
    raw = text.to_s
    return [] if raw.blank?

    lines = raw.split(/\r?\n|\/|、|,|，/).map(&:strip).reject(&:blank?)

    target_lines =
      if target_label.present?
        lines.select { |line| line.include?(target_label) }
      else
        lines
      end

    target_lines.flat_map do |line|
      line.scan(/(\d{1,2}:\d{2})\s*[-〜~－–—]\s*(\d{1,2}:\d{2})/).filter_map do |open_text, close_text|
        open_min = hhmm_to_min(open_text)
        close_min = hhmm_to_min(close_text)
        next if open_min.nil? || close_min.nil?

        [open_min, close_min]
      end
    end
  end
  def today_key
    %w[sunday monday tuesday wednesday thursday friday saturday][Time.zone.today.wday]
  end

  def hhmm_to_min(hhmm)
    return nil if hhmm.blank?

    m = hhmm.to_s.match(/\A(\d{1,2}):(\d{2})\z/)
    return nil unless m

    hour = m[1].to_i
    min = m[2].to_i

    return nil if min < 0 || min > 59
    return nil if hour < 0 || hour > 24
    return nil if hour == 24 && min != 0

    hour * 60 + min
  end

  def within_range?(now_min, start_min, end_min)
    return false if now_min.nil? || start_min.nil? || end_min.nil?

    # 00:00-24:00 は終日営業として扱う
    return true if start_min == 0 && end_min == 1440

    # 24:00 は当日終端として扱う
    if end_min == 1440
      return now_min >= start_min && now_min < 1440
    end

    if end_min > start_min
      now_min >= start_min && now_min < end_min
    else
      # 例: 18:00-05:00 のような日跨ぎ営業
      now_min >= start_min || now_min < end_min
    end
  end

  def truthy?(value)
    value == true || value.to_s == "1"
  end

  def geocoding_enabled?
    lookup = (Geocoder.config.lookup rescue nil).to_s
    if lookup.include?("google")
      key = ENV["GOOGLE_MAPS_API_KEY"].to_s.strip
      key = ENV["GMAPS_API_KEY"].to_s.strip if key.blank?
      return key.present?
    end
    true
  end

  def should_geocode?
    return false unless geocoding_enabled?
    return false if geocode_address.blank?

    address_changed = will_save_change_to_address?
    area_changed = will_save_change_to_area?
    missing_latlng = latitude.blank? || longitude.blank?

    address_changed || area_changed || missing_latlng
  end

  def last_confirmed_on_cannot_be_future
    return if last_confirmed_on.blank?

    errors.add(:last_confirmed_on, "は未来の日付にできません") if last_confirmed_on > Date.current
  end

  def set_normalized_phone
    digits = phone.to_s.gsub(/[^0-9]/, "")
    self.normalized_phone = digits.presence
  end

  def set_default_smoking_values
    self.smoking_area = "unknown" if smoking_area.blank?
    self.smoking_type = "unknown" if smoking_type.blank?
  end

  def safe_attachments(collection)
    return [] unless collection.respond_to?(:attachments)

    collection.attachments.select do |att|
      begin
        att.present? && att.blob.present? && att.blob.key.present?
      rescue StandardError
        false
      end
    end
  end

  def auto_thumbnail_attachments
    [
      safe_attachments(food_photos),
      safe_attachments(exterior_photos),
      safe_attachments(interior_photos),
      safe_attachments(menu_photos)
    ].flatten
  end

  def pick_attachment_from(attachments, idx)
    return nil if attachments.blank?

    picked = attachments[idx - 1] || attachments.first
    return nil unless picked.present?

    begin
      picked.blob
      picked
    rescue StandardError
      nil
    end
  end

  def place_id_column_available?
    self.class.column_names.include?("place_id") && respond_to?(:place_id)
  end

  def place_id_value
    return nil unless place_id_column_available?

    place_id
  rescue StandardError
    nil
  end

  def duplicate_scope_state(scope)
    return :approved_or_rejected if scope.where(approved: true).exists?
    return :approved_or_rejected if scope.where(rejected: true).exists?
    return :pending_only if scope.exists?

    :none
  rescue StandardError => e
    Rails.logger.warn("[duplicate_scope_state] #{e.class}: #{e.message}")
    :none
  end

  def duplicate_status_label(other)
    if other.approved?
      "承認済み"
    elsif other.respond_to?(:rejected?) && other.rejected?
      "却下済み"
    else
      "承認待ち"
    end
  rescue StandardError
    "状態不明"
  end
end