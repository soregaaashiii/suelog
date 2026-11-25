# frozen_string_literal: true

class GeographiesController < HomeController
  def index
    @directory = GeographicDirectory.new
    @regions = @directory.published("region")
    @stations = @directory.published("station")
    @seo_noindex = @regions.empty? && @stations.empty?
    @page_title = "大阪の地域・駅から喫煙できる店を探す｜吸えログ"
    @page_description = "大阪の市区町村・駅から飲食店を探せます。掲載店舗数と喫煙情報を確認し、席で喫煙可・喫煙所ありなどの条件で絞り込めます。"
    @canonical_url = geographic_directory_url
    track_page_view
  end

  def show
    set_default_page_meta!
    @directory = GeographicDirectory.new
    kind = request.path_parameters.fetch(:geographic_kind)
    @geographic_page = @directory.definition(kind, params[:slug])
    raise ActionController::RoutingError, "Not Found" unless @geographic_page

    @geographic_stats = @directory.stats(@geographic_page)
    raise ActionController::RoutingError, "Not Found" if @geographic_stats.fetch("count").zero?

    @geographic_scope = @directory.scope(@geographic_page)
    @seo_noindex = !@directory.published?(@geographic_page)
    label = @geographic_page.fetch("label")
    context = kind == "station" ? "#{label}周辺" : label
    @page_heading = "#{context}で喫煙できる店"
    @page_title = "#{@page_heading}｜席で喫煙可・喫煙所あり【吸えログ】"
    @page_description = "#{context}の掲載店舗#{@geographic_stats.fetch('count')}件から探せます。喫煙条件・確認状況・営業時間・地図を確認し、席で喫煙可や加熱式のみなどで絞り込めます。"
    @search_form_url = @directory.path(@geographic_page)
    @clear_filters_url = @search_form_url
    @canonical_url = "https://suelog.jp#{@search_form_url}"
    @forced_area_label = label
    track_page_view
    build_listing!
    @seo_noindex ||= @shops_count < GeographicDirectory::MIN_SHOPS
    render "home/index"
  end
end
