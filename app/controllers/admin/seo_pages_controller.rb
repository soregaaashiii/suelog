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

  def edit
    load_editor
  end

  def update_metadata
    load_editor
    attributes = params.fetch(:seo_page_setting, ActionController::Parameters.new).permit(:title, :description).to_h.symbolize_keys
    attributes = { title: nil, description: nil } if params[:commit_action] == "reset"
    result = SeoPageMetadataEditor.new(path: @row.fetch(:path), attributes: attributes,
      expected_version: params.dig(:seo_page_setting, :version), defaults: @generated,
      change_note: params.dig(:seo_page_setting, :change_note)).call
    redirect_to admin_edit_seo_page_path(page_path: @row.fetch(:path), filters: @return_filters), status: :see_other,
      flash: { admin_notice: result.changed ? "SEO設定を保存しました。変更履歴に記録しました。" : "設定の変更はありません。" }
  rescue SeoPageMetadataEditor::Conflict
    @conflicting_values = attributes
    @edit_error = "別の画面で設定が更新されています。現在の内容を再確認して編集してください。"
    load_editor
    render :edit, status: :conflict
  rescue ActiveRecord::RecordInvalid => e
    @setting = e.record
    @change_note = params.dig(:seo_page_setting, :change_note)
    render :edit, status: :unprocessable_entity
  end

  private

  def protect_seo_response
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    response.headers["Cache-Control"] = "no-store"
  end

  def import_attributes
    params.fetch(:search_console_import, ActionController::Parameters.new).permit(:period_start, :period_end, :previous_start, :previous_end, :search_context)
  end

  def load_editor
    @row = SeoPageCatalog.new.rows.find { |row| row.fetch(:path) == params[:page_path] }
    raise ActiveRecord::RecordNotFound unless @row
    definition = GeographicPageMetadata.definition(@row.fetch(:path))
    @generated = GeographicPageMetadata.generated(**definition, count: @row.fetch(:count))
    @setting = SeoPageSetting.find_or_initialize_by(path: @row.fetch(:path))
    @revisions = @setting.revisions.order(id: :desc).page(params[:history_page]).per(10)
    @return_filters = params.fetch(:filters, ActionController::Parameters.new).permit(:q, :kind, :status, :reason, :performance, :sort, :page, :import_id).to_h
    @report = @return_filters["import_id"].present? ? SearchConsoleImport.find(@return_filters["import_id"]) : SearchConsoleImport.order(id: :desc).first
    @performance_row = SearchConsolePerformance.new(@report).apply([@row]).first if @report
    @revision_comparisons = SeoRevisionPerformance.new(report: @report, setting: @setting, performance: @performance_row&.fetch(:performance)).apply(@revisions)
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
    @sort = (%w[shops_desc shops_asc url] + SearchConsolePerformance::SORTS.keys).include?(params[:sort]) ? params[:sort] : (@report ? "priority" : "shops_desc")
    rows = @catalog.search(query: @query, kind: @kind, status: @status, reason: @reason, sort: @sort)
    performance = SearchConsolePerformance.new(@report)
    @candidate_counts = performance.apply(@catalog.rows).each_with_object(Hash.new(0)) do |row, counts|
      row[:performance][:candidates].each { |flag| counts[flag] += 1 }
    end if @report
    rows = performance.apply(rows, filter: @performance_filter, sort: @sort)
    @rows = Kaminari.paginate_array(rows).page([params[:page].to_i, 1].max).per(50)
    @page_settings = SeoPageSetting.where(path: @rows.map { |row| row.fetch(:path) }).pluck(:path, :title, :description, :updated_at).to_h do |path, title, description, updated_at|
      [path, { customized: title.present? || description.present?, updated_at: updated_at }]
    end
    @editor_filters = { q: @query, kind: @kind, status: @status, reason: @reason, performance: @performance_filter, sort: @sort, page: @rows.current_page, import_id: @report&.id }.compact
  end
end
