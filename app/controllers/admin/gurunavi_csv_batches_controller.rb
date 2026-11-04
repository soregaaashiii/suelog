require "digest"
class Admin::GurunaviCsvBatchesController < Admin::BaseController
  before_action :load_batch, only: [ :show, :apply, :rollback, :review, :resume, :review_target, :rematch ]
  MAX_BYTES = 25 * 1024 * 1024
  def index
    @batches = GurunaviCsvBatch.metadata.order(id: :desc).limit(50)
  end
  def new; end
  def create
    upload = params[:file]
    raise ArgumentError, "shoplist.csvを選択してください" unless upload.respond_to?(:read)
    raise ArgumentError, "CSVファイルを指定してください" unless File.extname(upload.original_filename.to_s).downcase == ".csv"
    raise ArgumentError, "CSVは25MB以下にしてください" if upload.size > MAX_BYTES
    bytes = upload.read(MAX_BYTES + 1)
    raise ArgumentError, "CSVが空か25MBを超えています" if bytes.blank? || bytes.bytesize > MAX_BYTES
    batch = GurunaviCsvBatch.create!(filename: File.basename(upload.original_filename), source_bytes: bytes.b, sha256: Digest::SHA256.hexdigest(bytes), matching_basis: "shop", trial_mode: params[:trial_mode] == "1", area_filter: params[:area_filter].to_s.strip.presence)
    execution = batch.executions.create!(kind: "match", run_token: SecureRandom.uuid, heartbeat_at: Time.current)
    batch.events.create!(action: "uploaded", payload: { filename: batch.filename, sha256: batch.sha256, trial_mode: batch.trial_mode, area_filter: batch.area_filter })
    GurunaviCsvJob.perform_later(execution.id, execution.run_token)
    redirect_to admin_gurunavi_csv_batch_path(batch), status: :see_other
  rescue ArgumentError => e
    flash.now[:admin_alert] = e.message
    render :new, status: :unprocessable_entity
  end
  def show
    return show_shop_targets if @batch.shop_first?
    @counts = @batch.rows.group(:classification).count
    @states = @batch.rows.group(:state).count
    @classification, @state, @q = params[:classification].to_s, params[:state].to_s, params[:q].to_s.strip
    @page = [ params[:page].to_i, 1 ].max
    scope = @batch.rows.order(:line_number)
    scope = @classification.present? ? scope.where(classification: @classification) : scope.where.not(classification: "out_of_scope")
    scope = scope.where(state: @state) if @state.present?
    if @q.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      shop_ids = Shop.where("name LIKE :q OR address LIKE :q", q: like).select(:id)
      row_ids = GurunaviCsvMatch.where(shop_id: shop_ids, gurunavi_csv_row_id: @batch.rows.select(:id)).select(:gurunavi_csv_row_id)
      scope = scope.where("csv_name LIKE :q OR csv_address LIKE :q OR id IN (#{row_ids.to_sql})", q: like)
    end
    @total = scope.count
    @pages = [ (@total / 50.0).ceil, 1 ].max
    @rows = scope.offset((@page - 1) * 50).limit(50).includes(:matches).to_a
    @shops = Shop.where(id: @rows.flat_map { |r| r.matches.map(&:shop_id) }).select(:id, :name, :address, :gurunavi_url, :gurunavi_affiliate_url, :updated_at).index_by(&:id)
    @executions = @batch.executions.order(id: :desc).limit(20)
    @events = @batch.events.order(id: :desc).limit(50)
    @ready_count = ready_matches.count
    response.headers["Cache-Control"] = "no-store"
  end
  def apply
    raise GurunaviCsv::Review::Conflict, "確認チェックを入れてください" unless params[:reviewed] == "1"
    scope = ready_matches
    scope = scope.where(id: Array(params[:match_ids]).first(1000)) unless params[:mode] == "all_ready"
    enqueue("apply", scope.pluck(:id))
  rescue GurunaviCsv::Review::Conflict => e
    redirect_to admin_gurunavi_csv_batch_path(@batch), status: :see_other, flash: { admin_alert: e.message }
  end
  def rollback
    raise GurunaviCsv::Review::Conflict, "取り消し確認チェックを入れてください" unless params[:reviewed] == "1"
    scope = batch_matches.where(state: %w[applied rollback_conflict]).where.not(applied_at: nil)
    scope = scope.where(id: Array(params[:match_ids]).first(1000)) unless params[:mode] == "all_applied"
    enqueue("rollback", scope.pluck(:id))
  rescue GurunaviCsv::Review::Conflict => e
    redirect_to admin_gurunavi_csv_batch_path(@batch), status: :see_other, flash: { admin_alert: e.message }
  end
  def review
    row = @batch.rows.find(params[:row_id])
    match = row.matches.find(params[:match_id]) if params[:match_id].present?
    GurunaviCsv::Review.call(row, params[:decision].to_s, match: match, shop_id: params[:shop_id], allow_replace: params[:allow_replace] == "1")
    redirect_to admin_gurunavi_csv_batch_path(@batch, classification: params[:classification], q: params[:q], page: params[:page]), status: :see_other, flash: { admin_notice: "確認状態を保存しました。確定だけではURLは更新しません。" }
  rescue GurunaviCsv::Review::Conflict => e
    redirect_to admin_gurunavi_csv_batch_path(@batch), status: :see_other, flash: { admin_alert: e.message }
  end
  def review_target
    target = @batch.targets.find(params[:target_id])
    match = target.matches.find(params[:match_id]) if params[:match_id].present?
    GurunaviCsv::TargetReview.call(target, params[:decision].to_s, match: match, line_number: params[:line_number], allow_replace: params[:allow_replace] == "1")
    redirect_to admin_gurunavi_csv_batch_path(@batch, classification: params[:classification], q: params[:q], page: params[:page]), status: :see_other, flash: { admin_notice: "吸えログ店舗の確認状態を保存しました。URLはまだ更新していません。" }
  rescue GurunaviCsv::Review::Conflict => e
    redirect_to admin_gurunavi_csv_batch_path(@batch), status: :see_other, flash: { admin_alert: e.message }
  end
  def rematch
    source = GurunaviCsvBatch.find(@batch.id)
    batch = GurunaviCsvBatch.create!(filename: source.filename, sha256: source.sha256, source_bytes: source.source_bytes, matching_basis: "shop", trial_mode: source.trial_mode, area_filter: source.area_filter)
    execution = batch.executions.create!(kind: "match", run_token: SecureRandom.uuid, heartbeat_at: Time.current)
    batch.events.create!(action: "rematched_from", payload: { source_batch_id: source.id, matching_basis: "shop" })
    GurunaviCsvJob.perform_later(execution.id, execution.run_token)
    redirect_to admin_gurunavi_csv_batch_path(batch), status: :see_other, flash: { admin_notice: "同じCSVを使い、公開中の吸えログ店舗を起点に新しく照合します。過去の確認・登録履歴は保持します。" }
  end
  def resume
    execution = @batch.executions.find(params[:execution_id])
    execution.with_lock do
      raise GurunaviCsv::Review::Conflict, "処理中または完了済みです。処理中の再開は10分後から可能です。" unless execution.restartable?
      @batch.events.create!(gurunavi_csv_execution_id: execution.id, action: "resumed", payload: { previous_state: execution.state, previous_message: execution.message })
      execution.update!(state: "queued", run_token: SecureRandom.uuid, heartbeat_at: Time.current, processed_count: 0, message: "再開待ち")
    end
    GurunaviCsvJob.perform_later(execution.id, execution.run_token)
    redirect_to admin_gurunavi_csv_batch_path(@batch), status: :see_other
  rescue GurunaviCsv::Review::Conflict => e
    redirect_to admin_gurunavi_csv_batch_path(@batch), status: :see_other, flash: { admin_alert: e.message }
  end
  private
  def show_shop_targets
    @classification, @state, @q = params[:classification].to_s, params[:state].to_s, params[:q].to_s.strip
    @page = [ params[:page].to_i, 1 ].max
    @counts = @batch.targets.group(:classification).count
    @invalid_count = @batch.rows.where(classification: "invalid").count
    @executions = @batch.executions.order(id: :desc).limit(20)
    @events = @batch.events.order(id: :desc).limit(50)
    @ready_count = ready_matches.count
    if @classification == "invalid"
      scope = @batch.rows.where(classification: "invalid").order(:line_number)
      @total = scope.count
      @invalid_rows = scope.offset((@page - 1) * 50).limit(50)
      @targets = []
      @shops = {}
    else
      scope = @batch.targets.order(:shop_id)
      scope = scope.where(classification: @classification) if @classification.present?
      scope = scope.where(state: @state) if @state.present?
      if @q.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        shop_ids = Shop.where("name LIKE :q OR address LIKE :q", q: like).select(:id)
        source_rows = @batch.rows.where("csv_name LIKE :q OR csv_address LIKE :q", q: like).select(:id)
        target_ids = batch_matches.where(gurunavi_csv_row_id: source_rows).select(:gurunavi_csv_target_id)
        scope = scope.where("shop_id IN (#{shop_ids.to_sql}) OR shop_snapshot LIKE :q OR id IN (#{target_ids.to_sql})", q: like)
      end
      @total = scope.count
      @targets = scope.offset((@page - 1) * 50).limit(50).includes(matches: :gurunavi_csv_row).to_a
      @shops = Shop.where(id: @targets.map(&:shop_id)).select(:id, :name, :address, :gurunavi_url, :gurunavi_affiliate_url, :updated_at).index_by(&:id)
    end
    @pages = [ (@total / 50.0).ceil, 1 ].max
    response.headers["Cache-Control"] = "no-store"
    render :show
  end
  def load_batch = @batch = GurunaviCsvBatch.metadata.find(params[:id])
  def batch_matches = GurunaviCsvMatch.where(gurunavi_csv_row_id: @batch.rows.select(:id))
  def ready_matches
    if @batch.shop_first?
      return batch_matches.joins(:gurunavi_csv_target).where("(gurunavi_csv_matches.classification = 'bulk' AND gurunavi_csv_matches.state = 'pending' AND gurunavi_csv_targets.classification = 'bulk' AND gurunavi_csv_targets.state = 'pending') OR (gurunavi_csv_matches.state = 'confirmed' AND gurunavi_csv_targets.state = 'confirmed' AND gurunavi_csv_targets.selected_match_id = gurunavi_csv_matches.id)")
    end
    batch_matches.joins(:gurunavi_csv_row).where("(gurunavi_csv_matches.classification = 'bulk' AND gurunavi_csv_matches.state = 'pending' AND gurunavi_csv_rows.state = 'pending') OR (gurunavi_csv_matches.state = 'confirmed' AND gurunavi_csv_rows.state = 'confirmed' AND gurunavi_csv_rows.selected_match_id = gurunavi_csv_matches.id)")
  end
  def enqueue(kind, ids)
    raise GurunaviCsv::Review::Conflict, "対象候補を選択してください" if ids.empty?
    execution = nil
    GurunaviCsvBatch.transaction do
      batch = GurunaviCsvBatch.metadata.lock.find(@batch.id)
      raise GurunaviCsv::Review::Conflict, "照合完了後に操作してください" unless batch.state == "ready"
      raise GurunaviCsv::Review::Conflict, "別の処理を実行中です。完了または実行履歴から再開してください。" if batch.executions.where(state: %w[queued running]).exists?
      execution = batch.executions.create!(kind: kind, selection: ids, total_count: ids.size, run_token: SecureRandom.uuid, heartbeat_at: Time.current)
      batch.events.create!(gurunavi_csv_execution_id: execution.id, action: "#{kind}_requested", payload: { selected_match_ids: ids })
    end
    GurunaviCsvJob.perform_later(execution.id, execution.run_token)
    redirect_to admin_gurunavi_csv_batch_path(@batch), status: :see_other, flash: { admin_notice: "#{ids.size}件の#{kind == 'apply' ? '登録' : '取り消し'}を受け付けました。" }
  end
end
