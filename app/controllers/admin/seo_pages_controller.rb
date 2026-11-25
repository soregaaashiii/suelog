# frozen_string_literal: true

class Admin::SeoPagesController < Admin::BaseController
  before_action :protect_seo_response

  def index
    load_inventory
  end

  def import_csv
    @import_values = import_attributes.to_h
    report = SearchConsoleCsvImporter.new(current_file: params.dig(:search_console_import, :current_file),
      previous_file: params.dig(:search_console_import, :previous_file), attributes: @import_values).call
    redirect_to admin_seo_pages_path(import_id: report.id), status: :see_other,
      flash: { admin_notice: "検索実績を取り込みました。対象期間 #{report.statistics.dig('current', 'matched')}ページが一致しました。" }
  rescue SearchConsoleCsvImporter::InvalidCsv => e
    @import_error = e.message
    load_inventory
    render :index, status: :unprocessable_entity
  end

  private

  def protect_seo_response
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    response.headers["Cache-Control"] = "no-store"
  end

  def import_attributes
    params.fetch(:search_console_import, ActionController::Parameters.new).permit(:period_start, :period_end, :previous_start, :previous_end, :search_context)
  end

  def load_inventory
    @catalog = SeoPageCatalog.new
    @reports = SearchConsoleImport.order(id: :desc).limit(20).to_a
    @report = params[:import_id].present? ? SearchConsoleImport.find(params[:import_id]) : @reports.first
    @reports.unshift(@report) if @report && !@reports.include?(@report)
    @query = params[:q].to_s.strip.first(100)
    @kind = SeoPageCatalog::KINDS.key?(params[:kind]) ? params[:kind] : ""
    @status = SeoPageCatalog::STATUSES.key?(params[:status]) ? params[:status] : ""
    @reason = SeoPageCatalog::REASONS.key?(params[:reason]) ? params[:reason] : ""
    @performance_filter = SearchConsolePerformance::FILTERS.key?(params[:performance]) ? params[:performance] : ""
    @sort = (%w[shops_desc shops_asc url] + SearchConsolePerformance::SORTS.keys).include?(params[:sort]) ? params[:sort] : "shops_desc"
    rows = @catalog.search(query: @query, kind: @kind, status: @status, reason: @reason, sort: @sort)
    rows = SearchConsolePerformance.new(@report).apply(rows, filter: @performance_filter, sort: @sort)
    @rows = Kaminari.paginate_array(rows).page([params[:page].to_i, 1].max).per(50)
  end
end
