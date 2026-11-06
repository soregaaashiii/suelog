class Admin::HotpepperApiBatchesController < Admin::BaseController
  before_action :load_batch, only: [ :show, :apply, :rollback, :resume, :review_target, :refresh_candidates ]
  def index
    @batches = HotpepperApiBatch.metadata.order(id: :desc).limit(50)
  end
  def new
    redirect_to admin_hotpepper_api_batches_path
  end
  def create
    raise ArgumentError, "RenderにHOTPEPPER_API_KEYを設定してください" if ENV["HOTPEPPER_API_KEY"].blank?
    batch, execution = nil, nil
    HotpepperApiWriteLock.create_or_find_by!(name: "collection_start").with_lock do
      if HotpepperApiBatch.where(state: %w[queued processing]).exists?
        raise ArgumentError, "検索処理が実行中です。前回の作業から進捗を確認してください。"
      end
      batch = HotpepperApiBatch.create!(filename: "ホットペッパー公式API", sha256: SecureRandom.hex(32), source_bytes: "", matching_basis: "shop", trial_mode: params[:trial_mode] == "1", area_filter: params[:area_filter].to_s.strip.presence)
      execution = batch.executions.create!(kind: "match", run_token: SecureRandom.uuid, heartbeat_at: Time.current)
      batch.events.create!(action: "requested", payload: { trial_mode: batch.trial_mode, area_filter: batch.area_filter })
    end
    HotpepperApiJob.perform_later(execution.id, execution.run_token)
    redirect_to admin_hotpepper_api_batch_path(batch), status: :see_other
  rescue ArgumentError => e
    redirect_to admin_hotpepper_api_batches_path, status: :see_other, flash: { admin_alert: e.message }
  end
  def show
    show_shop_targets
  end
  def apply
    raise HotpepperApi::Review::Conflict, "確認チェックを入れてください" unless params[:reviewed] == "1"
    scope = ready_matches
    scope = scope.where(id: Array(params[:match_ids]).first(1000)) unless params[:mode] == "all_ready"
    enqueue("apply", scope.pluck(:id))
  rescue HotpepperApi::Review::Conflict => e
    redirect_to admin_hotpepper_api_batch_path(@batch), status: :see_other, flash: { admin_alert: e.message }
  end
  def rollback
    raise HotpepperApi::Review::Conflict, "取り消し確認チェックを入れてください" unless params[:reviewed] == "1"
    scope = batch_matches.where(state: %w[applied rollback_conflict]).where.not(applied_at: nil)
    scope = scope.where(id: Array(params[:match_ids]).first(1000)) unless params[:mode] == "all_applied"
    enqueue("rollback", scope.pluck(:id))
  rescue HotpepperApi::Review::Conflict => e
    redirect_to admin_hotpepper_api_batch_path(@batch), status: :see_other, flash: { admin_alert: e.message }
  end
  def review_target
    target = @batch.targets.find(params[:target_id])
    match = target.matches.find(params[:match_id]) if params[:match_id].present?
    if params[:decision] == "register"
      raise HotpepperApi::Review::Conflict, "候補を選択してください" unless match
      HotpepperApi::TargetReview.call(target, "confirm", match: match, allow_replace: params[:allow_replace] == "1")
      return enqueue("apply", [ match.id ], inline: true, target: target)
    elsif params[:decision] == "undo"
      raise HotpepperApi::Review::Conflict, "登録済みの候補を選択してください" unless match && %w[applied rollback_conflict].include?(match.state)
      return enqueue("rollback", [ match.id ], inline: true, target: target)
    end
    HotpepperApi::TargetReview.call(target, params[:decision].to_s, match: match, line_number: params[:line_number], allow_replace: params[:allow_replace] == "1")
    message = case params[:decision]
    when "exclude" then "この店舗の候補をすべて外しました。「除外済み」から戻せます。"
    when "restore" then "未登録一覧に戻しました。"
    else "吸えログ店舗の確認状態を保存しました。URLはまだ更新していません。"
    end
    return render json: { success: true, message: message, shop_id: target.shop_id } if request.format.json?
    redirect_to admin_hotpepper_api_batch_path(@batch, classification: params[:classification], q: params[:q], page: params[:page]), status: :see_other, flash: { admin_notice: message }
  rescue HotpepperApi::Review::Conflict => e
    return render json: { success: false, message: e.message }, status: :unprocessable_entity if request.format.json?
    redirect_to admin_hotpepper_api_batch_path(@batch), status: :see_other, flash: { admin_alert: e.message }
  end
  def refresh_candidates
    redirect_to admin_hotpepper_api_batches_path, status: :see_other, flash: { admin_notice: "新しいAPI検索を開始してください。以前の登録・作業履歴は残ります。" }
  end
  def resume
    execution = @batch.executions.find(params[:execution_id])
    execution.with_lock do
      raise HotpepperApi::Review::Conflict, "処理中または完了済みです。処理中の再開は10分後から可能です。" unless execution.restartable?
      @batch.events.create!(hotpepper_api_execution_id: execution.id, action: "resumed", payload: { previous_state: execution.state, previous_message: execution.message })
      execution.update!(state: "queued", run_token: SecureRandom.uuid, heartbeat_at: Time.current, processed_count: 0, message: "再開待ち")
    end
    HotpepperApiJob.perform_later(execution.id, execution.run_token)
    redirect_to admin_hotpepper_api_batch_path(@batch), status: :see_other
  rescue HotpepperApi::Review::Conflict => e
    redirect_to admin_hotpepper_api_batch_path(@batch), status: :see_other, flash: { admin_alert: e.message }
  end
  private
  def show_shop_targets
    @classification, @state, @q = params[:classification].to_s, "", params[:q].to_s.strip
    @page = [ params[:page].to_i, 1 ].max
    @counts = @batch.targets.unregistered.group(:classification).count
    @counts["registered"] = @batch.targets.registered.count
    @counts["excluded"] = @batch.targets.excluded.count
    @url_conflict_count = @batch.targets.url_conflicts.count
    @unregistered_count = @batch.targets.unregistered.count
    @invalid_count = @batch.rows.where(classification: "invalid").count
    @executions = @batch.executions.order(id: :desc).limit(20)
    @events = @batch.events.order(id: :desc).limit(50)
    @ready_count = ready_matches.count
    candidate_ids = HotpepperApiMatch.where(hotpepper_api_target_id: @batch.targets.select(:id)).select(:hotpepper_api_target_id)
    @candidate_confidence_counts = @batch.targets.where(id: candidate_ids).group(:confidence).count
    @remaining_confidence_counts = @batch.targets.unregistered.where(id: candidate_ids).group(:confidence).count
    if @classification == "invalid"
      scope = @batch.rows.where(classification: "invalid").order(:line_number)
      @total = scope.count
      @invalid_rows = scope.offset((@page - 1) * 50).limit(50)
      @targets = []
      @shops = {}
    else
      scope = case @classification
      when "registered" then @batch.targets.registered
      when "excluded" then @batch.targets.excluded
      when "url_conflict" then @batch.targets.url_conflicts
      else @batch.targets.unregistered
      end
      scope = scope.where(classification: @classification) if @classification.present? && !%w[registered excluded url_conflict].include?(@classification)
      if @q.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        shop_ids = Shop.where("name LIKE :q OR address LIKE :q", q: like).select(:id)
        source_rows = @batch.rows.where("csv_name LIKE :q OR csv_address LIKE :q", q: like).select(:id)
        target_ids = batch_matches.where(hotpepper_api_row_id: source_rows).select(:hotpepper_api_target_id)
        scope = scope.where("hotpepper_api_targets.shop_id IN (#{shop_ids.to_sql}) OR hotpepper_api_targets.shop_snapshot LIKE :q OR hotpepper_api_targets.id IN (#{target_ids.to_sql})", q: like)
      end
      @total = scope.count
      @page = [ @page, [ (@total / 50.0).ceil, 1 ].max ].min
      access_counts = PageView.where(is_bot: [ false, nil ]).where.not(shop_id: nil)
        .group(:shop_id).select("shop_id, COUNT(*) AS views_count")
      scope = scope.joins("LEFT JOIN (#{access_counts.to_sql}) csv_access ON csv_access.shop_id = hotpepper_api_targets.shop_id")
        .select("hotpepper_api_targets.*", "COALESCE(csv_access.views_count, 0) AS access_count")
        .order(Arel.sql("CASE WHEN EXISTS (SELECT 1 FROM hotpepper_api_matches WHERE hotpepper_api_matches.hotpepper_api_target_id = hotpepper_api_targets.id) THEN 0 ELSE 1 END ASC, hotpepper_api_targets.confidence DESC, COALESCE(csv_access.views_count, 0) DESC, hotpepper_api_targets.shop_id ASC"))
      @targets = scope.offset((@page - 1) * 50).limit(50).includes(matches: :hotpepper_api_row).to_a
      @shops = Shop.where(id: @targets.map(&:shop_id)).select(:id, :name, :address, :hotpepper_url, :hotpepper_affiliate_url, :updated_at).index_by(&:id)
    end
    @pages = [ (@total / 50.0).ceil, 1 ].max
    response.headers["Cache-Control"] = "no-store"
    render :show
  end
  def load_batch = @batch = HotpepperApiBatch.metadata.find(params[:id])
  def batch_matches = HotpepperApiMatch.where(hotpepper_api_row_id: @batch.rows.select(:id))
  def ready_matches
    if @batch.shop_first?
      return batch_matches.joins(:hotpepper_api_target).where("(hotpepper_api_matches.classification = 'bulk' AND hotpepper_api_matches.state = 'pending' AND hotpepper_api_targets.classification = 'bulk' AND hotpepper_api_targets.state = 'pending') OR (hotpepper_api_matches.state = 'confirmed' AND hotpepper_api_targets.state = 'confirmed' AND hotpepper_api_targets.selected_match_id = hotpepper_api_matches.id)")
    end
    batch_matches.joins(:hotpepper_api_row).where("(hotpepper_api_matches.classification = 'bulk' AND hotpepper_api_matches.state = 'pending' AND hotpepper_api_rows.state = 'pending') OR (hotpepper_api_matches.state = 'confirmed' AND hotpepper_api_rows.state = 'confirmed' AND hotpepper_api_rows.selected_match_id = hotpepper_api_matches.id)")
  end
  def enqueue(kind, ids, inline: false, target: nil)
    raise HotpepperApi::Review::Conflict, "対象候補を選択してください" if ids.empty?
    execution = nil
    HotpepperApiBatch.transaction do
      batch = HotpepperApiBatch.metadata.lock.find(@batch.id)
      raise HotpepperApi::Review::Conflict, "照合完了後に操作してください" unless batch.state == "ready"
      raise HotpepperApi::Review::Conflict, "別の処理を実行中です。完了または実行履歴から再開してください。" if batch.executions.where(state: %w[queued running]).exists?
      execution = batch.executions.create!(kind: kind, selection: ids, total_count: ids.size, run_token: SecureRandom.uuid, heartbeat_at: Time.current)
      batch.events.create!(hotpepper_api_execution_id: execution.id, action: "#{kind}_requested", payload: { selected_match_ids: ids })
    end
    if inline
      HotpepperApiJob.perform_now(execution.id, execution.run_token)
      match = batch_matches.find(ids.sole)
      success = match.state == (kind == "apply" ? "applied" : "rolled_back") || (kind == "apply" && match.state == "skipped")
      message = success ? (kind == "apply" ? "登録しました。間違えた場合は「取り消す」で戻せます。" : "登録を取り消しました。別の候補を選んで登録できます。") : (execution.reload.message.presence if execution.state == "failed") || match.reason
      if request.format.json?
        url_conflict = target.reload.state == "url_conflict"
        return render json: { success: success, remove_from_list: url_conflict, destination: url_conflict ? "conflict" : nil, message: url_conflict ? "他店舗に登録済みのため、競合一覧へ移しました。" : message, shop_id: target.shop_id }, status: success ? :ok : :unprocessable_entity
      end
      redirect_to admin_hotpepper_api_batch_path(@batch, classification: params[:classification], state: params[:state], q: params[:q], page: params[:page], anchor: "shop-#{target.shop_id}"), status: :see_other, flash: { (success ? :admin_notice : :admin_alert) => message }
    else
      HotpepperApiJob.perform_later(execution.id, execution.run_token)
      redirect_to admin_hotpepper_api_batch_path(@batch), status: :see_other, flash: { admin_notice: "#{ids.size}件の#{kind == 'apply' ? '登録' : '取り消し'}を受け付けました。" }
    end
  end
end
