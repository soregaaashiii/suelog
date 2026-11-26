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

    @facets = GeographicFacets.new(@directory)
    if request.path_parameters[:facet_kind]
      @geographic_facet = @facets.definition(request.path_parameters[:facet_kind], request.path_parameters[:facet])
      raise ActionController::RoutingError, "Not Found" unless @geographic_facet
    end
    @geographic_stats = @geographic_facet ? @facets.stats(@geographic_page, @geographic_facet) : @directory.stats(@geographic_page)
    raise ActionController::RoutingError, "Not Found" if @geographic_stats.fetch("count").zero?

    @geographic_scope = @geographic_facet ? @facets.scope(@geographic_page, @geographic_facet) : @directory.scope(@geographic_page)
    @seo_noindex = !@directory.published?(@geographic_page)
    label = @geographic_page.fetch("label")
    generated = GeographicPageMetadata.generated(entry: @geographic_page, facet: @geographic_facet, count: @geographic_stats.fetch("count"))
    @page_heading = generated.fetch(:heading)
    @page_title = generated.fetch(:title)
    @page_description = generated.fetch(:description)
    @search_form_url = @geographic_facet ? @facets.path(@geographic_page, @geographic_facet) : @directory.path(@geographic_page)
    if @geographic_facet
      @facet_decision = @facets.decision(@geographic_page, @geographic_facet)
      @seo_noindex ||= !@facet_decision.fetch(:published)
      @forced_genre_label = @geographic_facet.fetch("label") if @geographic_facet.fetch("kind") == "genre"
    end
    if (setting = SeoPageSetting.find_by(path: @search_form_url))
      effective = setting.effective(generated)
      @page_title = effective.fetch(:title)
      @page_description = effective.fetch(:description)
    end
    @clear_filters_url = @search_form_url
    @canonical_url = "https://suelog.jp#{@facet_decision ? @facet_decision.fetch(:canonical) : @search_form_url}"
    @forced_area_label = label
    track_page_view
    build_listing!
    @seo_noindex ||= @shops_count < GeographicDirectory::MIN_SHOPS
    if !@seo_noindex && request.query_parameters.empty?
      @geographic_guide = GeographicPageGuide.new(directory: @directory, facets: @facets, entry: @geographic_page, facet: @geographic_facet)
    end
    render "home/index"
  end
end
