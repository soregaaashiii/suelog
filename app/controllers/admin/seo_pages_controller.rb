# frozen_string_literal: true

class Admin::SeoPagesController < Admin::BaseController
  def index
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    response.headers["Cache-Control"] = "no-store"
    @catalog = SeoPageCatalog.new
    @query = params[:q].to_s.strip.first(100)
    @kind = SeoPageCatalog::KINDS.key?(params[:kind]) ? params[:kind] : ""
    @status = SeoPageCatalog::STATUSES.key?(params[:status]) ? params[:status] : ""
    @reason = SeoPageCatalog::REASONS.key?(params[:reason]) ? params[:reason] : ""
    @sort = %w[shops_desc shops_asc url].include?(params[:sort]) ? params[:sort] : "shops_desc"
    rows = @catalog.search(query: @query, kind: @kind, status: @status, reason: @reason, sort: @sort)
    @rows = Kaminari.paginate_array(rows).page([params[:page].to_i, 1].max).per(50)
  end
end
