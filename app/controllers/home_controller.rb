# /Users/kawamuratakuya/dev/suelog/app/controllers/home_controller.rb
# frozen_string_literal: true

class HomeController < ApplicationController
  AREA_GENRE_MAP = {
    "izakaya" => {
      label: "居酒屋",
      terms: ["居酒屋"]
    },
    "bar" => {
      label: "バー・パブ",
      terms: ["バー", "パブ", "ハブ", "ラウンジ"]
    },
    "cafe" => {
      label: "カフェ",
      terms: ["カフェ", "喫茶店", "カフェバー"]
    },
    "yakiniku" => {
      label: "焼肉",
      terms: ["焼肉"]
    }
  }.freeze

  STATION_SLUG_MAP = {
    "umeda" => {
      "osaka" => "大阪駅",
      "umeda" => "梅田駅",
      "higashi-umeda" => "東梅田駅",
      "nishi-umeda" => "西梅田駅",
      "kitashinchi" => "北新地駅",
      "nakazakicho" => "中崎町駅",
      "nakatsu" => "中津駅",
      "fukushima" => "福島駅"
    },
    "namba" => {
      "namba" => "なんば駅",
      "nanba" => "難波駅",
      "jr-namba" => "JR難波駅",
      "osaka-namba" => "大阪難波駅",
      "shinsaibashi" => "心斎橋駅",
      "nipponbashi" => "日本橋駅",
      "daikokucho" => "大国町駅",
      "sakuragawa" => "桜川駅"
    }
  }.freeze

  SORT_OPTIONS = %w[recommended rating reviews_count newest].freeze
  FULLWIDTH_SPACE = "\u3000"

  def index
    track_page_view

    set_default_page_meta!
    apply_area_page_context_from_params!

    build_listing!
    render :index
  end

  def umeda
    track_page_view

    set_default_page_meta!
    apply_umeda_context!

    build_listing!
    render :index
  end

  def umeda_genre
    track_page_view

    set_default_page_meta!
    apply_umeda_genre_context!

    build_listing!
    render :index
  end

  def namba
    track_page_view

    set_default_page_meta!
    apply_namba_context!

    build_listing!
    render :index
  end

  def namba_genre
    track_page_view

    set_default_page_meta!
    apply_namba_genre_context!

    build_listing!
    render :index
  end

  private

  def set_default_page_meta!
    @search_form_url = root_path
    @clear_filters_url = root_path
    @page_title = "吸えログ in大阪｜大阪で喫煙できる飲食店を探せる"
    @page_description = "大阪で喫煙できる飲食店を探せる吸えログ。席で喫煙可・喫煙所あり・加熱式のみなどの情報を掲載しています。"
    @page_heading = "掲載店舗"
    @page_subtitle = "大阪の喫煙可能店舗を一覧で確認できます"
    @area_intro_title = nil
    @area_intro_text = nil
    @canonical_url = root_url
    @is_area_page = false
    @area_nav_links = []
    @forced_area_keyword = nil
    @forced_area_label = nil
    @forced_genre = nil
    @forced_genre_slug = nil
    @forced_genre_label = nil
    @forced_genre_terms = []
    @forced_station_keyword = nil
    @forced_station_label = nil
    @current_area_key = current_area_key
    @pagination_params = {}
  end

  def current_area_key
  return "namba" if request.path.start_with?("/namba")
  return "umeda" if request.path.start_with?("/umeda")

  request.path_parameters[:area].presence || params[:area].presence
end

  def station_area_override
    return nil unless station_route_request?

    slug = current_station_slug.to_s
    return nil if slug.blank?

    matched_areas = STATION_SLUG_MAP.select { |_area, stations| stations.key?(slug) }.keys
    return matched_areas.first if matched_areas.one?

    nil
  end

  def apply_area_page_context_from_params!
    case current_area_key.to_s
    when "umeda"
      if station_route_request?
        apply_umeda_station_context!
      elsif genre_route_request?
        apply_umeda_genre_context!
      else
        apply_umeda_context!
      end
    when "namba"
      if station_route_request?
        apply_namba_station_context!
      elsif genre_route_request?
        apply_namba_genre_context!
      else
        apply_namba_context!
      end
    end
  end

  def apply_umeda_context!
    @forced_area_keyword = "梅田"
    @forced_area_label = "梅田"
    @forced_genre = nil
    @forced_genre_slug = nil
    @forced_genre_label = nil
    @forced_genre_terms = []
    @forced_station_keyword = nil
    @forced_station_label = nil
    @is_area_page = true
    @search_form_url = umeda_path
    @clear_filters_url = umeda_path
    @area_nav_links = umeda_nav_links
    @current_area_key = "umeda"

    smoking_area = normalized_smoking_area_param

    case smoking_area
    when "all_smoking"
      @page_title = "梅田で席で吸える店まとめ｜席で喫煙可の飲食店一覧【吸えログ】"
      @page_description = "梅田で席で喫煙可の飲食店を掲載。席でそのまま吸える店を探したい人向けに、喫煙タイプ・最寄駅・営業時間をまとめています。"
      @page_heading = "梅田で席で吸える店"
      @page_subtitle = "梅田エリアで席で喫煙可の店舗を一覧で確認できます"
      @area_intro_title = "梅田で席で吸える店を探す"
      @area_intro_text = "梅田で席で吸える飲食店をまとめています。移動せずにその場で吸いたい人、飲み会や仕事帰りに使いやすい店を探したい人向けの一覧です。"
      @canonical_url = umeda_smoking_url("all_smoking")
      @clear_filters_url = umeda_smoking_path("all_smoking")
    when "separated"
      @page_title = "梅田で喫煙所ありの店まとめ｜喫煙可の飲食店一覧【吸えログ】"
      @page_description = "梅田で喫煙所ありの飲食店を掲載。完全禁煙は困るけれど、喫煙場所が分かれている店を探したい人向けに最寄駅や営業時間も確認できます。"
      @page_heading = "梅田で喫煙所ありの店"
      @page_subtitle = "梅田エリアで喫煙所ありの店舗を一覧で確認できます"
      @area_intro_title = "梅田で喫煙所ありの店を探す"
      @area_intro_text = "梅田で喫煙所ありの飲食店をまとめています。吸える場所が明確な店を探したい人向けに、使いやすい喫煙可能店を一覧で見られます。"
      @canonical_url = umeda_smoking_url("separated")
      @clear_filters_url = umeda_smoking_path("separated")
    else
      @page_title = "梅田で喫煙可の店まとめ｜席で吸える・喫煙所あり【吸えログ】"
      @page_description = "梅田で喫煙できる飲食店を掲載。席で喫煙可・喫煙所あり・加熱式のみ対応など、梅田の喫煙可能店をまとめて探せます。"
      @page_heading = "梅田で喫煙できる店"
      @page_subtitle = "梅田エリアの喫煙可能店舗を一覧で確認できます"
      @area_intro_title = "梅田で喫煙可の店を探す"
      @area_intro_text = "梅田で喫煙できる飲食店をまとめています。席で吸える店、喫煙所ありの店、加熱式のみ対応の店などをまとめて探したい人向けの入口ページです。"
      @canonical_url = umeda_url
      @clear_filters_url = umeda_path
    end
  end

  def apply_umeda_genre_context!
    genre_config = current_area_genre_config
    raise ActionController::RoutingError, "Not Found" if genre_config.blank?

    genre_label = genre_config[:label]

    @forced_area_keyword = "梅田"
    @forced_area_label = "梅田"
    @forced_genre = genre_label
    @forced_genre_slug = current_genre_slug
    @forced_genre_label = genre_label
    @forced_genre_terms = Array(genre_config[:terms])
    @forced_station_keyword = nil
    @forced_station_label = nil
    @is_area_page = true
    @search_form_url = umeda_genre_path(current_genre_slug)
    @clear_filters_url = umeda_genre_path(current_genre_slug)
    @area_nav_links = umeda_nav_links
    @current_area_key = "umeda"

    @page_title = "梅田で喫煙できる#{genre_label}まとめ｜喫煙可の店一覧【吸えログ】"
    @page_description = "梅田で喫煙できる#{genre_label}を掲載。喫煙エリア、喫煙タイプ、最寄駅、営業時間を確認しながら使いやすい店を探せます。"
    @page_heading = "梅田で喫煙できる#{genre_label}"
    @page_subtitle = "梅田エリアの喫煙可能な#{genre_label}を一覧で確認できます"
    @area_intro_title = "梅田で喫煙できる#{genre_label}を探す"
    @area_intro_text = "梅田で喫煙できる#{genre_label}をまとめています。飲み会、仕事帰り、1人利用などに合わせて喫煙可能店を探しやすい一覧ページです。"
    @canonical_url = umeda_genre_url(current_genre_slug)
  end

  def apply_umeda_station_context!
    station_label = current_station_label
    raise ActionController::RoutingError, "Not Found" if station_label.blank?

    @forced_area_keyword = "梅田"
    @forced_area_label = "梅田"
    @forced_genre = nil
    @forced_genre_slug = nil
    @forced_genre_label = nil
    @forced_genre_terms = []
    @forced_station_keyword = station_label
    @forced_station_label = station_label
    @is_area_page = true
    @search_form_url = umeda_station_path(current_station_slug)
    @clear_filters_url = umeda_station_path(current_station_slug)
    @area_nav_links = umeda_nav_links + umeda_station_nav_links
    @current_area_key = "umeda"

    @page_title = "#{station_label}周辺で喫煙できる店｜席で吸える・喫煙所あり【吸えログ】"
    @page_description = "#{station_label}周辺で喫煙できる飲食店を掲載。#{station_label}近くで席で喫煙可の店、喫煙所ありの店、加熱式のみ対応の店などを探せます。"
    @page_heading = "#{station_label}周辺で喫煙できる店"
    @page_subtitle = "#{station_label}近くの喫煙可能店舗を一覧で確認できます"
    @area_intro_title = "#{station_label}周辺で喫煙できる店を探す"
    @area_intro_text = "#{station_label}近くで喫煙できる店をまとめています。吸える居酒屋、バー、カフェなどを探したい人向けに、席で喫煙可・喫煙所あり・加熱式のみ対応の店を一覧で見られます。仕事帰りや待ち合わせ前後に入りやすい、#{station_label}周辺の喫煙可能店を探したいときの入口ページとして使えます。"
    @canonical_url = umeda_station_url(current_station_slug)
  end

  def apply_namba_context!
    @forced_area_keyword = "難波"
    @forced_area_label = "難波"
    @forced_genre = nil
    @forced_genre_slug = nil
    @forced_genre_label = nil
    @forced_genre_terms = []
    @forced_station_keyword = nil
    @forced_station_label = nil
    @is_area_page = true
    @search_form_url = namba_path
    @clear_filters_url = namba_path
    @area_nav_links = namba_nav_links
    @current_area_key = "namba"

    smoking_area = normalized_smoking_area_param

    case smoking_area
    when "all_smoking"
      @page_title = "難波で席で吸える店まとめ｜席で喫煙可の飲食店一覧【吸えログ】"
      @page_description = "難波で席で喫煙可の飲食店を掲載。席でそのまま吸える店を探したい人向けに、喫煙タイプ・最寄駅・営業時間をまとめています。"
      @page_heading = "難波で席で吸える店"
      @page_subtitle = "難波エリアで席で喫煙可の店舗を一覧で確認できます"
      @area_intro_title = "難波で席で吸える店を探す"
      @area_intro_text = "難波で席で吸える飲食店をまとめています。移動せずその場で吸いたい人や、二軒目・待ち合わせ前に使いやすい店を探したい人向けです。"
      @canonical_url = namba_smoking_url("all_smoking")
      @clear_filters_url = namba_smoking_path("all_smoking")
    when "separated"
      @page_title = "難波で喫煙所ありの店まとめ｜喫煙可の飲食店一覧【吸えログ】"
      @page_description = "難波で喫煙所ありの飲食店を掲載。完全禁煙は困るけれど、喫煙場所が分かれている店を探したい人向けに最寄駅や営業時間も確認できます。"
      @page_heading = "難波で喫煙所ありの店"
      @page_subtitle = "難波エリアで喫煙所ありの店舗を一覧で確認できます"
      @area_intro_title = "難波で喫煙所ありの店を探す"
      @area_intro_text = "難波で喫煙所ありの飲食店をまとめています。喫煙場所が明確な店を探したい人向けに、使いやすい喫煙可能店を一覧で見られます。"
      @canonical_url = namba_smoking_url("separated")
      @clear_filters_url = namba_smoking_path("separated")
    else
      @page_title = "難波で喫煙可の店まとめ｜席で吸える・喫煙所あり【吸えログ】"
      @page_description = "難波で喫煙できる飲食店を掲載。席で喫煙可・喫煙所あり・加熱式のみ対応など、難波の喫煙可能店をまとめて探せます。"
      @page_heading = "難波で喫煙できる店"
      @page_subtitle = "難波エリアの喫煙可能店舗を一覧で確認できます"
      @area_intro_title = "難波で喫煙可の店を探す"
      @area_intro_text = "難波で喫煙できる飲食店をまとめています。席で吸える店、喫煙所ありの店、加熱式のみ対応の店などをまとめて探したい人向けの入口ページです。"
      @canonical_url = namba_url
      @clear_filters_url = namba_path
    end
  end

  def apply_namba_genre_context!
    genre_config = current_area_genre_config
    raise ActionController::RoutingError, "Not Found" if genre_config.blank?

    genre_label = genre_config[:label]

    @forced_area_keyword = "難波"
    @forced_area_label = "難波"
    @forced_genre = genre_label
    @forced_genre_slug = current_genre_slug
    @forced_genre_label = genre_label
    @forced_genre_terms = Array(genre_config[:terms])
    @forced_station_keyword = nil
    @forced_station_label = nil
    @is_area_page = true
    @search_form_url = namba_genre_path(current_genre_slug)
    @clear_filters_url = namba_genre_path(current_genre_slug)
    @area_nav_links = namba_nav_links
    @current_area_key = "namba"

    @page_title = "難波で喫煙できる#{genre_label}まとめ｜喫煙可の店一覧【吸えログ】"
    @page_description = "難波で喫煙できる#{genre_label}を掲載。喫煙エリア、喫煙タイプ、最寄駅、営業時間を確認しながら使いやすい店を探せます。"
    @page_heading = "難波で喫煙できる#{genre_label}"
    @page_subtitle = "難波エリアの喫煙可能な#{genre_label}を一覧で確認できます"
    @area_intro_title = "難波で喫煙できる#{genre_label}を探す"
    @area_intro_text = "難波で喫煙できる#{genre_label}をまとめています。飲み会、二軒目、休憩などに合わせて喫煙可能店を探しやすい一覧ページです。"
    @canonical_url = namba_genre_url(current_genre_slug)
  end

  def apply_namba_station_context!
    station_label = current_station_label
    raise ActionController::RoutingError, "Not Found" if station_label.blank?

    @forced_area_keyword = "難波"
    @forced_area_label = "難波"
    @forced_genre = nil
    @forced_genre_slug = nil
    @forced_genre_label = nil
    @forced_genre_terms = []
    @forced_station_keyword = station_label
    @forced_station_label = station_label
    @is_area_page = true
    @search_form_url = namba_station_path(current_station_slug)
    @clear_filters_url = namba_station_path(current_station_slug)
    @area_nav_links = namba_nav_links + namba_station_nav_links
    @current_area_key = "namba"

    @page_title = "#{station_label}周辺で喫煙できる店｜席で吸える・喫煙所あり【吸えログ】"
    @page_description = "#{station_label}周辺で喫煙できる飲食店を掲載。#{station_label}近くで席で喫煙可の店、喫煙所ありの店、加熱式のみ対応の店などを探せます。"
    @page_heading = "#{station_label}周辺で喫煙できる店"
    @page_subtitle = "#{station_label}近くの喫煙可能店舗を一覧で確認できます"
    @area_intro_title = "#{station_label}周辺で喫煙できる店を探す"
    @area_intro_text = "#{station_label}近くで喫煙できる店をまとめています。吸える居酒屋、バー、カフェなどを探したい人向けに、席で喫煙可・喫煙所あり・加熱式のみ対応の店を一覧で見られます。移動前後や待ち合わせの合間に入りやすい、#{station_label}周辺の喫煙可能店を探したいときの入口ページとして使えます。"
    @canonical_url = namba_station_url(current_station_slug)
  end

  def current_genre_slug
    route_genre_slug.presence
  end

  def route_genre_slug
    request.path_parameters[:genre].to_s.presence
  end

  def current_area_genre_config
    AREA_GENRE_MAP[route_genre_slug.to_s]
  end

  def station_route_request?
    request.path_parameters[:station].present?
  end

  def genre_route_request?
    route_genre_slug.present? && params[:genre].blank?
  end

  def current_station_slug
    request.path_parameters[:station].to_s.presence
  end

  def current_station_label
    area_key = @current_area_key.presence || current_area_key.to_s
    slug = current_station_slug.to_s
    mapped = STATION_SLUG_MAP.dig(area_key, slug)
    return mapped if mapped.present?

    fallback_mapped = STATION_SLUG_MAP.values.map { |stations| stations[slug] }.compact.first
    return fallback_mapped if fallback_mapped.present?
    return nil if slug.blank?

    slug.tr("-", " ").strip
  end

  def build_listing!
    @per = params[:per].to_i
    @per = 30 unless [30, 50, 100].include?(@per)

    @current_sort = normalized_sort_param
    @open_now_only = open_now_only_param?
    @listing_query = cleaned_listing_query
    @pagination_params = pagination_params_for_links

    genre_terms = effective_genre_terms
    station_q = effective_station_query
    smoking_area = normalized_smoking_area_param
    smoking_type = params[:smoking_type].to_s.strip
    keyword_q = normalized_keyword_query(params[:q])

    base = Shop
      .approved
      .left_joins(:reviews)
      .select(
        "shops.*",
        "COALESCE(AVG(CASE WHEN reviews.approved THEN reviews.rating END), 0) AS avg_rating",
        "COALESCE(SUM(CASE WHEN reviews.approved THEN 1 ELSE 0 END), 0) AS reviews_count",
        "MAX(CASE WHEN reviews.approved THEN reviews.created_at END) AS latest_review_at"
      )
      .group("shops.id")

    if @forced_area_keyword.present?
      like = "%#{@forced_area_keyword}%"
      area_sql = <<~SQL.squish
        shops.area LIKE :like
        OR shops.address LIKE :like
        OR shops.nearest_station LIKE :like
      SQL
      base = base.where(area_sql, like: like)
    end

    if genre_terms.present?
      genre_sql_parts = []
      genre_bindings = {}

      genre_terms.each_with_index do |term, idx|
        key = :"genre_like_#{idx}"
        genre_sql_parts << "(shops.genre LIKE :#{key} OR shops.genre_other LIKE :#{key})"
        genre_bindings[key] = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      end

      genre_sql = genre_sql_parts.join(" OR ")
      base = base.where(genre_sql, genre_bindings)
    end

    if station_q.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(station_q)}%"
      base = base.where("shops.nearest_station LIKE ?", like)
    end

    if smoking_area.present?
      smoking_area_value = Shop.smoking_areas[smoking_area]
      base = base.where(shops: { smoking_area: smoking_area_value }) if smoking_area_value.present?
    end

    if smoking_type.present?
      smoking_type_value = Shop.smoking_types[smoking_type]
      base = base.where(shops: { smoking_type: smoking_type_value }) if smoking_type_value.present?
    end

    if keyword_q.present?
      keyword_tokens = keyword_q.split(" ")
      keyword_tokens.each do |token|
        base = base.merge(Shop.keyword(token))
      end
    end

    if params[:needs_review].present?
      cutoff = 2.years.ago.to_date
      base = base.where("shops.last_confirmed_on IS NULL OR shops.last_confirmed_on < ?", cutoff)
    end

    records = base.to_a
    records.select!(&:open_now?) if @open_now_only
    records = sort_shop_records(records, @current_sort)

    @shops_count = records.size

    requested_page = params[:page].to_i
    requested_page = 1 if requested_page < 1

    paginated = Kaminari.paginate_array(records).page(requested_page).per(@per)

    if paginated.total_pages.positive? && requested_page > paginated.total_pages
      paginated = Kaminari.paginate_array(records).page(1).per(@per)
    end

    @shops = paginated
  end

  def effective_genre_param
    return normalized_genre_param(params[:genre]) if params[:genre].present?

    @forced_genre.presence
  end

  def effective_genre_terms
    if params[:genre].present?
      normalized = normalized_genre_param(params[:genre])

      if AREA_GENRE_MAP.key?(normalized)
        Array(AREA_GENRE_MAP[normalized][:terms]).flat_map { |term| Shop.genre_search_terms(term) }.uniq
      else
        Shop.genre_search_terms(normalized)
      end
    elsif @forced_genre_terms.present?
      @forced_genre_terms.flat_map { |term| Shop.genre_search_terms(term) }.uniq
    else
      Shop.genre_search_terms(effective_genre_param)
    end
  end

  def normalized_genre_param(value)
    raw = value.to_s.strip
    return raw if raw.blank?

    if AREA_GENRE_MAP.key?(raw)
      raw
    else
      AREA_GENRE_MAP.find { |_slug, config| config[:label] == raw }&.first || raw
    end
  end

  def effective_station_query
    return @forced_station_label if @forced_station_label.present?
    return @forced_station_keyword if @forced_station_keyword.present?

    params[:station].to_s.strip
  end

  def normalized_smoking_area_param
    value = request.path_parameters[:smoking_area].presence || params[:smoking_area].to_s.strip
    return "all_smoking" if value == "smoking_allowed"

    value
  end

  def normalized_sort_param
    value = params[:sort].to_s.strip
    return "recommended" if value.blank?
    return value if SORT_OPTIONS.include?(value)

    "recommended"
  end

  def open_now_only_param?
    ActiveModel::Type::Boolean.new.cast(params[:open_now_only])
  end

  def cleaned_listing_query
    request.query_parameters.to_h.except("page", "commit", "area").each_with_object({}) do |(key, value), hash|
      next if value.blank?
      next if station_route_request? && key == "station"
      next if genre_route_request? && key == "genre"
      next if request.path_parameters[:smoking_area].present? && key == "smoking_area"

      hash[key] = value
    end
  end

  def pagination_params_for_links
  route_params = {}

  route_params[:area] = @current_area_key if @current_area_key.present?
  route_params[:station] = current_station_slug if station_route_request?
  route_params[:genre] = current_genre_slug if genre_route_request?
  route_params[:smoking_area] = request.path_parameters[:smoking_area] if request.path_parameters[:smoking_area].present?

  route_params.merge(@listing_query || {}).merge(per: @per)
end



  def normalized_keyword_query(value)
    value.to_s
         .unicode_normalize(:nfkc)
         .tr(FULLWIDTH_SPACE, " ")
         .downcase
         .gsub(/\s+/, " ")
         .strip
  end

  def sort_shop_records(records, sort_key)
    records.sort_by do |shop|
      avg_rating = shop.try(:avg_rating).to_f
      reviews_count = shop.try(:reviews_count).to_i
      created_at_i = shop.created_at&.to_i || 0
      open_penalty = shop.open_now? ? 0 : 1

      case sort_key
      when "rating"
        [-avg_rating, -reviews_count, open_penalty, -created_at_i]
      when "reviews_count"
        [-reviews_count, -avg_rating, open_penalty, -created_at_i]
      when "newest"
        [-created_at_i, -avg_rating, -reviews_count, open_penalty]
      else
        [-avg_rating, -reviews_count, open_penalty, -created_at_i]
      end
    end
  end

  def umeda_nav_links
    [
      { label: "梅田すべて", path: umeda_path },
      { label: "梅田で席で喫煙可", path: umeda_smoking_path("all_smoking") },
      { label: "梅田で喫煙所あり", path: umeda_smoking_path("separated") },
      { label: "梅田の居酒屋", path: umeda_genre_path("izakaya") },
      { label: "梅田のバー", path: umeda_genre_path("bar") },
      { label: "梅田のカフェ", path: umeda_genre_path("cafe") },
      { label: "梅田の焼肉", path: umeda_genre_path("yakiniku") }
    ]
  end

  def namba_nav_links
    [
      { label: "難波すべて", path: namba_path },
      { label: "難波で席で喫煙可", path: namba_smoking_path("all_smoking") },
      { label: "難波で喫煙所あり", path: namba_smoking_path("separated") },
      { label: "難波の居酒屋", path: namba_genre_path("izakaya") },
      { label: "難波のバー", path: namba_genre_path("bar") },
      { label: "難波のカフェ", path: namba_genre_path("cafe") },
      { label: "難波の焼肉", path: namba_genre_path("yakiniku") }
    ]
  end

  def umeda_station_nav_links
    [
      { label: "大阪駅周辺", path: umeda_station_path("osaka") },
      { label: "梅田駅周辺", path: umeda_station_path("umeda") },
      { label: "東梅田駅周辺", path: umeda_station_path("higashi-umeda") },
      { label: "西梅田駅周辺", path: umeda_station_path("nishi-umeda") }
    ]
  end

  def namba_station_nav_links
    [
      { label: "なんば駅周辺", path: namba_station_path("namba") },
      { label: "難波駅周辺", path: namba_station_path("nanba") },
      { label: "JR難波駅周辺", path: namba_station_path("jr-namba") },
      { label: "大阪難波駅周辺", path: namba_station_path("osaka-namba") }
    ]
  end
end