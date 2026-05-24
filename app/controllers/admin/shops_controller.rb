# frozen_string_literal: true

require "csv"
require "json"
require "date"
require "digest"
require "cgi"

class Admin::ShopsController < Admin::BaseController
  def index
    @status = params[:status].presence || "pending"
    @source = params[:source].to_s.presence
    @q = params[:q].to_s.strip

    @per = (params[:per].presence || 50).to_i
    @per = 50 if @per <= 0
    @per = 500 if @per > 500

    @page = params[:page].to_i
    @page = 1 if @page <= 0

    scope = Shop.order(created_at: :desc)

    case @status
    when "rejected"
      scope = scope.where(rejected: true)
    when "all"
      # all
    when "unverified"
      scope = scope.where(smoking_unverified: true)
    when "hold"
      scope = scope.where(on_hold: true)
    when "tabelog_suspect"
      scope = scope.where.not(tabelog_candidate_url: [nil, ""])
    when "tabelog_missing"
      scope = scope
        .where(approved: true)
        .where(tabelog_affiliate_url: [nil, ""])
        .where.not("COALESCE(tabelog_url, '') LIKE ?", "https://not-found.local/%")
        .joins("LEFT JOIN shop_clicks ON shop_clicks.shop_id = shops.id")
        .group("shops.id")
        .reorder(Arel.sql("COUNT(shop_clicks.id) DESC, shops.created_at DESC"))
    else
      scope = scope.where(approved: false).where(rejected: [false, nil]).where(on_hold: [false, nil])
    end

    if @source.present? && Shop.column_names.include?("source")
      scope = scope.where(source: @source)
    end

    if @q.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      scope = scope.where(
        "shops.name LIKE :like OR shops.address LIKE :like OR shops.area LIKE :like OR shops.nearest_station LIKE :like OR shops.phone LIKE :like",
        like: like
      )
    end

    @total_count =
      if @status == "tabelog_missing"
        scope.except(:select, :group, :order).distinct.count(:id)
      else
        scope.count
      end

    @total_pages = (@total_count.to_f / @per).ceil
    @total_pages = 1 if @total_pages <= 0

    offset = (@page - 1) * @per
    @shops = scope.offset(offset).limit(@per)

    @duplicate_states = build_duplicate_states_for(@shops)
  end

  def clicks
    @status = params[:status].presence || "approved"
    @source = params[:source].to_s.presence
    @q = params[:q].to_s.strip
    @sort = params[:sort].presence || "clicks_desc"

    @per = (params[:per].presence || 50).to_i
    @per = 50 if @per <= 0
    @per = 500 if @per > 500

    @page = params[:page].to_i
    @page = 1 if @page <= 0

    scope = Shop.order(created_at: :desc)

    case @status
    when "approved"
      scope = scope.where(approved: true)
    when "rejected"
      scope = scope.where(rejected: true)
    when "pending"
      scope = scope.where(approved: false).where(rejected: [false, nil]).where(on_hold: [false, nil])
    when "unverified"
      scope = scope.where(smoking_unverified: true)
    when "hold"
      scope = scope.where(on_hold: true)
    else
      # all
    end

    if @source.present? && Shop.column_names.include?("source")
      scope = scope.where(source: @source)
    end

    if @q.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      scope = scope.where(
        "shops.name LIKE :like OR shops.address LIKE :like OR shops.area LIKE :like OR shops.nearest_station LIKE :like OR shops.phone LIKE :like",
        like: like
      )
    end

    shop_ids = scope.pluck(:id)

    @shop_click_counts = {}
    @article_shop_clicks_by_shop_id = {}
    click_totals_by_shop_id = {}

    if defined?(ShopClick) && shop_ids.present?
      raw_click_counts = ShopClick
        .where(shop_id: shop_ids)
        .group(:shop_id, :kind)
        .count

      @article_shop_clicks_by_shop_id =
        ShopClick
          .where(shop_id: shop_ids, kind: "article_shop_click")
          .includes(:article)
          .group_by(&:shop_id)

      shop_ids.each do |shop_id|
        phone = raw_click_counts[[shop_id, "phone_click"]].to_i
        map = raw_click_counts[[shop_id, "map_click"]].to_i
        affiliate = raw_click_counts[[shop_id, "affiliate_click"]].to_i
        article_shop = raw_click_counts[[shop_id, "article_shop_click"]].to_i
        total = phone + map + affiliate + article_shop

        article_flow_rate =
          if total.positive?
            ((article_shop.to_f / total) * 100).round(1)
          else
            0.0
          end

        @shop_click_counts[shop_id] = {
          total: total,
          phone_click: phone,
          map_click: map,
          affiliate_click: affiliate,
          article_shop_click: article_shop,
          article_flow_rate: article_flow_rate
        }

        click_totals_by_shop_id[shop_id] = total
      end
    end

    sorted_ids =
      case @sort
      when "clicks_asc"
        shop_ids.sort_by { |id| [click_totals_by_shop_id[id].to_i, -id] }
      when "name_asc"
        scope.reorder(name: :asc, id: :desc).pluck(:id)
      when "newest"
        scope.reorder(created_at: :desc, id: :desc).pluck(:id)
      when "oldest"
        scope.reorder(created_at: :asc, id: :asc).pluck(:id)
      else
        shop_ids.sort_by { |id| [-click_totals_by_shop_id[id].to_i, -id] }
      end

    @total_count = sorted_ids.size
    @total_pages = (@total_count.to_f / @per).ceil
    @total_pages = 1 if @total_pages <= 0

    paged_ids = sorted_ids.slice((@page - 1) * @per, @per) || []

    shops_by_id = Shop.where(id: paged_ids).index_by(&:id)
    @shops = paged_ids.map { |id| shops_by_id[id] }.compact

    render :clicks
  end

  def holds
    @shops = Shop
      .where(on_hold: true)
      .order(held_at: :desc, updated_at: :desc)
  end

  def phone_check_holds
    @shops = Shop
      .where(approved: true)
      .where(smoking_unverified: true)
      .where(phone_check_on_hold: true)
      .order(updated_at: :desc)
  end

  def hold_phone_check
    shop = Shop.find(params[:id])

    shop.update!(
      phone_check_on_hold: true,
      updated_at: Time.current
    )

    redirect_to smoking_unverified_admin_shops_path(per: params[:per], page: params[:page], open_now: params[:open_now]),
                flash: { admin_notice: "電話確認保留に移動しました：#{shop.name}" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to smoking_unverified_admin_shops_path(per: params[:per], page: params[:page], open_now: params[:open_now]),
                flash: { admin_alert: "電話確認保留への移動に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  end

  def resume_phone_check
    shop = Shop.find(params[:id])

    shop.update!(
      phone_check_on_hold: false,
      updated_at: Time.current
    )

    redirect_to phone_check_holds_admin_shops_path,
                flash: { admin_notice: "電話確認ページに戻しました：#{shop.name}" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to phone_check_holds_admin_shops_path,
                flash: { admin_alert: "電話確認ページへの復帰に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  end

  def smoking_unverified
    @per = (params[:per].presence || 100).to_i
    @per = 100 if @per <= 0
    @per = 500 if @per > 500

    @page = params[:page].to_i
    @page = 1 if @page <= 0

    @open_now = params[:open_now] == "1"
    @phone_check_hold = params[:phone_check_hold] == "1"

    scope = Shop
      .where(approved: true)
      .where(smoking_unverified: true)

    scope =
      if @phone_check_hold
        scope.where(phone_check_on_hold: true)
      else
        scope.where(phone_check_on_hold: [false, nil])
      end

    if @open_now
      scope = scope.select { |shop| shop.respond_to?(:open_now?) && shop.open_now? }
      shop_ids = scope.map(&:id)

      scope = Shop.where(id: shop_ids)
    end

    scope = scope
      .joins("LEFT JOIN shop_clicks ON shop_clicks.shop_id = shops.id")
      .select("shops.*, COUNT(shop_clicks.id) AS click_count")
      .group("shops.id")
      .order(Arel.sql("COUNT(shop_clicks.id) DESC, shops.updated_at DESC"))

    @total_count = scope.except(:select, :group, :order).distinct.count(:id)
    @total_pages = (@total_count.to_f / @per).ceil
    @total_pages = 1 if @total_pages <= 0

    @shops = scope.offset((@page - 1) * @per).limit(@per)
  end

  def show
    @shop = Shop.find(params[:id])
    @status = params[:status].presence || "pending"
    @source = params[:source].to_s.presence
    @per = (params[:per].presence || 50).to_i
    @page = (params[:page].presence || 1).to_i

    @duplicate_candidates =
      if @shop.respond_to?(:duplicate_candidates)
        @shop.duplicate_candidates(limit: 10)
      else
        []
      end

    @click_counts = {
      total: 0,
      phone_click: 0,
      map_click: 0,
      affiliate_click: 0,
      article_shop_click: 0
    }

    @article_shop_clicks =
      if @shop.respond_to?(:shop_clicks)
        @shop.shop_clicks
             .where(kind: "article_shop_click")
             .includes(:article)
             .order(created_at: :desc)
             .limit(30)
      else
        []
      end

    @article_shop_clicks_by_article =
      @article_shop_clicks
        .group_by(&:article)
        .transform_values(&:count)

    if @shop.respond_to?(:shop_clicks)
      grouped_counts = @shop.shop_clicks.group(:kind).count
      @click_counts[:phone_click] = grouped_counts["phone_click"].to_i
      @click_counts[:map_click] = grouped_counts["map_click"].to_i
      @click_counts[:affiliate_click] = grouped_counts["affiliate_click"].to_i
      @click_counts[:article_shop_click] = grouped_counts["article_shop_click"].to_i
      @click_counts[:total] =
        @click_counts[:phone_click] +
        @click_counts[:map_click] +
        @click_counts[:affiliate_click] +
        @click_counts[:article_shop_click]
    end
  end

  def new
    @shop = Shop.new
    @shop.last_confirmed_on ||= Date.current if @shop.respond_to?(:last_confirmed_on)
    @shop.smoking_unverified = true if @shop.respond_to?(:smoking_unverified=) && @shop.smoking_unverified.nil?

    if @shop.respond_to?(:approved=) && @shop.approved.nil?
      @shop.approved = false
    end

    if @shop.respond_to?(:rejected=) && @shop.rejected.nil?
      @shop.rejected = false
    end

    if @shop.respond_to?(:on_hold=) && @shop.on_hold.nil?
      @shop.on_hold = false
    end

    @status = params[:status].presence || "pending"
    @source = params[:source].to_s.presence
    @per = (params[:per].presence || 50).to_i
    @page = (params[:page].presence || 1).to_i
  end

  def create
    @shop = Shop.new(shop_params)
    @status = params[:status].presence || "pending"
    @source = params[:source].to_s.presence
    @per = (params[:per].presence || 50).to_i
    @page = (params[:page].presence || 1).to_i

    action = params[:commit_action].to_s
    notice = "店舗を登録しました"

    ActiveRecord::Base.transaction do
      normalize_admin_shop_defaults!(@shop)
      populate_derived_hours_fields!(@shop)

      @shop.save!

      case action
      when "approve"
        if duplicate_exists_against_approved_shops?(@shop)
          raise ActiveRecord::RecordInvalid.new(
            @shop.tap do |s|
              s.errors.add(:base, "承認済み店舗との重複の可能性があるため承認できません。詳細から重複候補を確認してください。")
            end
          )
        end

        attrs = {
          approved: true,
          rejected: false,
          on_hold: false
        }
        attrs[:held_at] = nil if Shop.column_names.include?("held_at")

        @shop.update!(attrs)
        notice = "店舗を登録して承認しました"
      when "reject"
        attrs = {
          approved: false,
          rejected: true,
          on_hold: false
        }
        attrs[:held_at] = nil if Shop.column_names.include?("held_at")

        @shop.update!(attrs)
        notice = "店舗を登録して却下しました"
      when "hold"
        attrs = {
          approved: false,
          rejected: false,
          on_hold: true
        }
        attrs[:held_at] = Time.current if Shop.column_names.include?("held_at")

        @shop.update!(attrs)
        notice = "店舗を登録して保留に移動しました"
      end
    end

    redirect_to admin_shops_path(status: @status, source: @source, per: @per, page: @page),
                flash: { admin_notice: notice }
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:admin_alert] = e.record.errors.full_messages.join(" / ")
    render :new, status: :unprocessable_entity
  end

  def approve
    status = params[:status].presence || "pending"
    shop = Shop.find(params[:id])

    if duplicate_exists_against_approved_shops?(shop)
      redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                  alert: "承認済み店舗との重複の可能性があるため承認できません。詳細から重複候補を確認してください。"
      return
    end

    attrs = {
      approved: true,
      rejected: false,
      on_hold: false
    }
    attrs[:held_at] = nil if Shop.column_names.include?("held_at")

    shop.update!(attrs)

    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_notice: "承認しました" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_alert: "承認に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  end

  def reject
    status = params[:status].presence || "pending"
    shop = Shop.find(params[:id])

    attrs = {
      approved: false,
      rejected: true,
      on_hold: false
    }
    attrs[:held_at] = nil if Shop.column_names.include?("held_at")

    shop.update!(attrs)

    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_alert: "却下しました" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_alert: "却下に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  end

  def hold
    status = params[:status].presence || "pending"
    shop = Shop.find(params[:id])

    attrs = {
      approved: false,
      rejected: false,
      on_hold: true
    }
    attrs[:held_at] = Time.current if Shop.column_names.include?("held_at")

    shop.update!(attrs)

    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_notice: "保留に移動しました" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_alert: "保留への移動に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  end

  def approve_tabelog_candidate
    status = params[:status].presence || "tabelog_suspect"
    shop = Shop.find(params[:id])

    candidate_url = shop.tabelog_candidate_url.to_s.strip
    candidate_affiliate_url =
      shop.tabelog_candidate_affiliate_url.to_s.strip.presence ||
      build_tabelog_affiliate_url(candidate_url)

    if candidate_url.blank?
      redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                  flash: { admin_alert: "食べログ候補URLがありません" }
      return
    end

    shop.update!(
      tabelog_url: candidate_url,
      tabelog_affiliate_url: candidate_affiliate_url,
      tabelog_matched_at: Time.current,
      tabelog_match_method: "admin_approved_candidate",
      tabelog_candidate_url: nil,
      tabelog_candidate_affiliate_url: nil,
      tabelog_candidate_matched_at: nil,
      tabelog_candidate_method: nil
    )

    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_notice: "食べログ候補を承認しました" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_alert: "食べログ候補の承認に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  end

  def confirm_smoking_info
    shop = Shop.find(params[:id])

    attrs = {
      smoking_unverified: false,
      updated_at: Time.current
    }
    attrs[:last_confirmed_on] = Date.current if Shop.column_names.include?("last_confirmed_on")

    shop.update!(attrs)

    redirect_to smoking_unverified_admin_shops_path(per: params[:per], page: params[:page]),
                flash: { admin_notice: "喫煙情報を確認済みにしました：#{shop.name}" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to smoking_unverified_admin_shops_path(per: params[:per], page: params[:page]),
                flash: { admin_alert: "確認済みへの更新に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  end

  def update_smoking_info
    shop = Shop.find(params[:id])

    attrs = params.require(:shop).permit(:smoking_area, :smoking_type).to_h
    attrs[:smoking_unverified] = false
    attrs[:updated_at] = Time.current
    attrs[:last_confirmed_on] = Date.current if Shop.column_names.include?("last_confirmed_on")

    current_note = shop.note.to_s
    note_lines = []

    if params[:confirmed_partitioned] == "1"
      note_lines << "[分煙確認 #{Date.current.strftime('%Y-%m-%d')}]"
    end

    if params[:confirmed_all_smoking] == "1"
      note_lines << "[全席喫煙確認 #{Date.current.strftime('%Y-%m-%d')}]"
    end

    note_lines = note_lines.reject { |line| current_note.include?(line) }

    if note_lines.present?
      attrs[:note] = [
        current_note,
        *note_lines
      ].reject(&:blank?).join("\n")
    end

    shop.update!(attrs)

    redirect_to smoking_unverified_admin_shops_path(per: params[:per], page: params[:page], open_now: params[:open_now], phone_check_hold: params[:phone_check_hold]),
                flash: { admin_notice: "喫煙情報を更新して確認済みにしました：#{shop.name}" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to smoking_unverified_admin_shops_path(per: params[:per], page: params[:page], open_now: params[:open_now]),
                flash: { admin_alert: "喫煙情報の更新に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  rescue ActionController::ParameterMissing
    redirect_to smoking_unverified_admin_shops_path(per: params[:per], page: params[:page], open_now: params[:open_now]),
                flash: { admin_alert: "喫煙情報の入力がありません" }
  end

  def move_to_hold_from_smoking_check
    shop = Shop.find(params[:id])
    reason = params[:reason].presence || "確認結果"

    attrs = {
      approved: false,
      rejected: false,
      on_hold: true,
      smoking_unverified: false,
      updated_at: Time.current
    }
    attrs[:held_at] = Time.current if Shop.column_names.include?("held_at")

    shop.update!(attrs)

    redirect_to smoking_unverified_admin_shops_path(per: params[:per], page: params[:page]),
                flash: { admin_notice: "#{reason}のため保留に移動しました：#{shop.name}" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to smoking_unverified_admin_shops_path(per: params[:per], page: params[:page]),
                flash: { admin_alert: "保留への移動に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  end

  def mark_tabelog_not_found
    status = params[:status].presence || "tabelog_suspect"
    shop = Shop.find(params[:id])

    dummy_url = "https://not-found.local/#{Time.zone.today.strftime('%y%m%d')}"

    shop.update!(
      tabelog_url: dummy_url,
      tabelog_affiliate_url: nil,
      tabelog_matched_at: Time.current,
      tabelog_match_method: "admin_not_found",
      tabelog_candidate_url: nil,
      tabelog_candidate_affiliate_url: nil,
      tabelog_candidate_matched_at: nil,
      tabelog_candidate_method: nil
    )

    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_notice: "食べログなしとしてダミーURLを登録しました" }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                flash: { admin_alert: "ダミーURL登録に失敗しました：#{e.record.errors.full_messages.join(' / ')}" }
  end

  def bulk_update
    status = params[:status].presence || "pending"

    ids =
      Array(params[:shop_ids]).presence ||
      params[:shop_ids_csv].to_s.split(",")

    ids = ids.map(&:to_i).uniq
    op = params[:operation].to_s

    if ids.empty?
      return redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                         alert: "店舗が選択されていません"
    end

    scope = Shop.where(id: ids)

    case op
    when "approve"
      approved_count = 0
      skipped_count = 0

      scope.find_each do |shop|
        if duplicate_exists_against_approved_shops?(shop)
          Rails.logger.info("[SKIP DUPLICATE APPROVE] #{shop.id}")
          skipped_count += 1
          next
        end

        attrs = {
          approved: true,
          rejected: false,
          on_hold: false
        }
        attrs[:held_at] = nil if Shop.column_names.include?("held_at")

        shop.update!(attrs)
        approved_count += 1
      end

      message = "一括承認しました（#{approved_count}件）"
      message += " / 承認済み店舗との重複の可能性でスキップ（#{skipped_count}件）" if skipped_count.positive?

      redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                  flash: { admin_notice: message }
    when "reject"
      attrs = {
        approved: false,
        rejected: true,
        on_hold: false,
        updated_at: Time.current
      }
      attrs[:held_at] = nil if Shop.column_names.include?("held_at")

      scope.update_all(attrs)

      redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                  flash: { admin_alert: "一括却下しました（#{ids.size}件）" }
    when "unverify"
      scope.update_all(smoking_unverified: false, updated_at: Time.current)
      redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                  flash: { admin_notice: "未確認を解除しました（#{ids.size}件）" }
    else
      redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
                  flash: { admin_alert: "不正な操作です" }
    end
  end

  def edit
    @shop = Shop.find(params[:id])
    @status = params[:status].presence || "pending"
    @source = params[:source].to_s.presence
    @per = (params[:per].presence || 50).to_i
    @page = (params[:page].presence || 1).to_i
  end

  def update
    @shop = Shop.find(params[:id])
    Rails.logger.warn("SHOP_PARAMS_RAW=#{params[:shop].inspect}")

    action = params[:commit_action].to_s
    notice = "更新しました"

    ActiveRecord::Base.transaction do
      permitted_shop_params = shop_params

      if permitted_shop_params.key?(:tabelog_candidate_url) &&
         permitted_shop_params[:tabelog_candidate_url].blank?
        permitted_shop_params = permitted_shop_params.except(
          :tabelog_candidate_url,
          :tabelog_candidate_affiliate_url,
          :tabelog_candidate_method
        )
      end

      if permitted_shop_params.key?(:tabelog_url) &&
         permitted_shop_params[:tabelog_url].blank?
        permitted_shop_params = permitted_shop_params.except(
          :tabelog_url,
          :tabelog_affiliate_url,
          :tabelog_match_method
        )
      end

      if permitted_shop_params[:tabelog_url].present?
        permitted_shop_params[:tabelog_affiliate_url] =
          build_tabelog_affiliate_url(permitted_shop_params[:tabelog_url])
        permitted_shop_params[:tabelog_match_method] =
          permitted_shop_params[:tabelog_match_method].presence || "admin_manual"
      end

      if permitted_shop_params[:tabelog_candidate_url].present?
        permitted_shop_params[:tabelog_candidate_affiliate_url] =
          build_tabelog_affiliate_url(permitted_shop_params[:tabelog_candidate_url])
        permitted_shop_params[:tabelog_candidate_method] =
          permitted_shop_params[:tabelog_candidate_method].presence || "admin_manual_candidate"
      end

      @shop.update!(permitted_shop_params)
      purge_removed_photos!(@shop)
      attach_uploaded_photos!(@shop)
      populate_derived_hours_fields!(@shop)
      @shop.save! if @shop.changed?

      case action
      when "approve"
        if duplicate_exists_against_approved_shops?(@shop)
          raise ActiveRecord::RecordInvalid.new(
            @shop.tap do |s|
              s.errors.add(:base, "承認済み店舗との重複の可能性があるため承認できません。詳細から重複候補を確認してください。")
            end
          )
        end

        attrs = {
          approved: true,
          rejected: false,
          on_hold: false
        }
        attrs[:held_at] = nil if Shop.column_names.include?("held_at")

        @shop.update!(attrs)
        notice = "更新して承認しました"
      when "reject"
        attrs = {
          approved: false,
          rejected: true,
          on_hold: false
        }
        attrs[:held_at] = nil if Shop.column_names.include?("held_at")

        @shop.update!(attrs)
        notice = "更新して却下しました"
      when "hold"
        attrs = {
          approved: false,
          rejected: false,
          on_hold: true
        }
        attrs[:held_at] = Time.current if Shop.column_names.include?("held_at")

        @shop.update!(attrs)
        notice = "更新して保留に移動しました"
      end
    end

    if params[:from] == "shop_import"
      redirect_to new_admin_shop_import_path,
                  flash: { admin_notice: notice }
    elsif params[:from] == "clicks"
      redirect_to admin_shop_clicks_path(
        status: params[:status],
        source: params[:source],
        per: params[:per],
        page: params[:page],
        q: params[:q],
        sort: params[:sort]
      ),
                  flash: { admin_notice: notice }
    else
      redirect_to admin_shops_path(
        status: params[:status],
        source: params[:source],
        per: params[:per],
        page: params[:page]
      ),
                  flash: { admin_notice: notice }
    end
  rescue ActiveRecord::RecordInvalid => e
    @status = params[:status].presence || "pending"
    @source = params[:source].to_s.presence
    @per = (params[:per].presence || 50).to_i
    @page = (params[:page].presence || 1).to_i

    flash.now[:admin_alert] = e.record.errors.full_messages.join(" / ")
    render :edit, status: :unprocessable_entity
  end

  def import
    file = params[:file]
    return redirect_to admin_shops_path, flash: { admin_alert: "CSVファイルを選択してください" } unless file

    success = 0
    failed = 0
    skipped_duplicates = 0
    skipped_blank = 0
    processed_rows = 0
    raw_rows = 0
    error_messages = []

    area_map = {
      "umeda" => "梅田",
      "namba" => "難波",
      "tennoji" => "天王寺",
      "shinsaibashi" => "心斎橋",
      "kyobashi" => "京橋",
      "shinosaka" => "新大阪",
      "yodoyabashi" => "淀屋橋",
      "hommachi" => "本町"
    }

    normalize_str = lambda do |v|
      return "" if v.nil?

      s = v.is_a?(String) ? v : v.to_s
      s = s.tr("０-９", "0-9")
      s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
    end

    pick = lambda do |row, keys|
      normalized_row_hash =
        row.to_h.each_with_object({}) do |(header, value), h|
          normalized_header =
            header.to_s
                  .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                  .sub(/\A\uFEFF/, "")
                  .strip
                  .downcase

          h[normalized_header] = value
        end

      keys.each do |k|
        v = normalized_row_hash[k.to_s.strip.downcase]
        return v if v.present?
      end

      nil
    end

    map_smoking_area = lambda do |raw|
      s = normalize_str.call(raw)
      return nil if s.blank?

      case s
      when "0" then "separated"
      when "1" then "all_smoking"
      when "2" then "separated"
      else s.presence
      end
    end

    map_smoking_type = lambda do |raw|
      s = normalize_str.call(raw)
      return nil if s.blank?

      case s
      when "0" then "both_ok"
      when "1" then "electronic_only"
      when "2" then "paper_only"
      when "3" then "paper_only"
      else s.presence
      end
    end

    begin
      csv_text = file.read
      csv_text = csv_text.to_s
      csv_text = csv_text.force_encoding("UTF-8")
      csv_text = csv_text.sub(/\A\uFEFF/, "")

      Rails.logger.warn(
        "[CSV UPLOAD DEBUG] filename=#{file.original_filename} size=#{csv_text.bytesize} sha256=#{Digest::SHA256.hexdigest(csv_text)} valid_encoding=#{csv_text.valid_encoding?}"
      )

      rows = CSV.parse(
        csv_text,
        headers: true,
        encoding: "UTF-8",
        liberal_parsing: true,
        quote_char: '"'
      )

      if rows.empty?
        return redirect_to admin_shops_path, flash: { admin_alert: "CSVのデータ行が0件です。ヘッダだけ、またはCSV形式が不正です。" }
      end

      Rails.logger.info("[CSV IMPORT] headers=#{rows.headers.inspect}")

      rows.each_with_index do |row, idx|
        raw_rows += 1

        raw_genre_value = nil
        raw_genre_other_value = nil
        genre = nil
        genre_other = nil

        begin
          row_hash = row.to_h

          if row_hash.values.all? { |v| normalize_str.call(v).blank? }
            skipped_blank += 1
            Rails.logger.info("[CSV IMPORT SKIP BLANK] line=#{idx + 2}")
            next
          end

          headers = row.headers.map do |header|
            header.to_s
                  .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                  .sub(/\A\uFEFF/, "")
                  .strip
                  .downcase
          end

          fields = row.fields
          collector_csv =
            headers.include?("place_id") &&
            headers.include?("maps_url") &&
            headers.include?("name") &&
            headers.include?("genre") &&
            headers.include?("address")

          name = normalize_str.call(pick.call(row, [:name, "name", "店名"]))
          phone = normalize_str.call(pick.call(row, [:phone, "phone", "電話番号"]))
          address = normalize_str.call(pick.call(row, [:address, "address", "住所", "formatted_address"]))

          if fields.size >= 11 && fields[1].to_s.include?("query_place_id=")
            name = normalize_str.call(fields[2]) if name.blank?
            address = normalize_str.call(fields[4]) if address.blank? || address.match?(/\A\d{3}-?\d{4}(?:\s+\d+)?\z/)
            phone = normalize_str.call(fields[10]) if phone.blank?
          end

          if name.blank? && address.blank? && phone.blank?
            skipped_blank += 1
            Rails.logger.info("[CSV IMPORT SKIP EMPTY KEY FIELDS] line=#{idx + 2} row=#{row_hash.inspect}")
            next
          end

          processed_rows += 1

          attrs = {
            name: name,
            address: address,
            phone: phone
          }

          Rails.logger.warn(
            "[CSV DUP CHECK] line=#{idx + 2} name=#{name.inspect} address=#{address.inspect} phone=#{phone.inspect}"
          )

          if Shop.duplicate_exists_for_import?(attrs)
            skipped_duplicates += 1
            Rails.logger.info("[SKIP DUPLICATE] line=#{idx + 2} #{name} / #{address}")
            next
          end

          opening_hours_text = normalize_str.call(
            pick.call(row, [:opening_hours_text, "opening_hours_text", "通常営業時間", "営業時間テキスト"])
          )
          holiday_hours_text = normalize_str.call(
            pick.call(row, [:holiday_hours_text, "holiday_hours_text", "祝日営業時間"])
          )
          closed_days_text = normalize_str.call(
            pick.call(row, [:closed_days_text, "closed_days_text", "定休日"])
          )

          opening_json_raw = pick.call(row, [:opening_hours_json, "opening_hours_json", "営業時間JSON"])
          opening_text_legacy = normalize_str.call(
            pick.call(row, [:opening_hours, "opening_hours", "営業時間", "hours"])
          )

          opening_json =
            if opening_json_raw.present?
              begin
                parsed = JSON.parse(opening_json_raw.to_s)
                OpeningHoursParser.normalize_json(parsed)
              rescue JSON::ParserError
                OpeningHoursParser.parse_legacy_text(opening_text_legacy)
              end
            elsif opening_text_legacy.present?
              OpeningHoursParser.parse_legacy_text(opening_text_legacy)
            else
              {}
            end

          area_raw = normalize_str.call(pick.call(row, [:area, "area", "エリア"]))
          nearest_station = normalize_str.call(pick.call(row, [:nearest_station, "nearest_station", "最寄駅"]))
          note = normalize_str.call(pick.call(row, [:note, "note", "メモ"]))
          public_store_details = normalize_str.call(
            pick.call(row, [:public_store_details, "public_store_details", "店舗詳細", "詳細"])
          )

          raw_genre_value = pick.call(row, [:genre, "genre", "ジャンル"])
          raw_genre_other_value = pick.call(row, [:genre_other, "genre_other", "ジャンルその他", "その他"])

          genre = normalize_str.call(raw_genre_value)

          if fields.size >= 11 && fields[1].to_s.include?("query_place_id=")
            genre = normalize_str.call(fields[3]) if genre.blank?
          end

          if genre.blank? && raw_genre_other_value.present?
            genre = normalize_str.call(raw_genre_other_value)
          end

          # 最後の保険：ジャンルが空なら「その他」で取り込む
          genre = "その他" if genre.blank?
          genre_other = normalize_str.call(raw_genre_other_value)

          Rails.logger.warn(
            "[CSV GENRE DEBUG] line=#{idx + 2} raw_genre=#{raw_genre_value.inspect} normalized_genre=#{genre.inspect} raw_genre_other=#{raw_genre_other_value.inspect} row_keys=#{row.to_h.keys.inspect}"
          )

          smoking_area = map_smoking_area.call(pick.call(row, [:smoking_area, "smoking_area", "喫煙エリア"]))
          smoking_type = map_smoking_type.call(pick.call(row, [:smoking_type, "smoking_type", "喫煙タイプ"]))

          tabelog_url = normalize_str.call(
            pick.call(row, [:tabelog_url, "tabelog_url", "食べログURL", "tabelog"])
          )
          tabelog_affiliate_url = normalize_str.call(
            pick.call(row, [:tabelog_affiliate_url, "tabelog_affiliate_url", :affiliate_url, "affiliate_url", "食べログアフィリエイトURL"])
          )
          hotpepper_url = normalize_str.call(
            pick.call(row, [:hotpepper_url, "hotpepper_url", "ホットペッパーURL", "hotpepper"])
          )

          last_raw = normalize_str.call(
            pick.call(row, [:last_confirmed_on, "last_confirmed_on", "最終確認日"])
          )

          last_confirmed_on =
            if last_raw.present?
              if last_raw.match?(/\A\d{6}\z/)
                year = ("20" + last_raw[0..1]).to_i
                month = last_raw[2..3].to_i
                day = last_raw[4..5].to_i
                Date.new(year, month, day)
              else
                Date.parse(last_raw)
              end
            else
              Date.current
            end

          area_key = area_raw.to_s.downcase
          area = area_map[area_key] || area_raw

          shop = Shop.new(
            name: name,
            phone: phone.presence,
            address: address,
            area: area.presence,
            nearest_station: nearest_station.presence,
            opening_hours_text: opening_hours_text.presence,
            holiday_hours_text: holiday_hours_text.presence,
            closed_days_text: closed_days_text.presence,
            opening_hours_json: opening_json,
            note: note.presence,
            public_store_details: public_store_details.presence,
            genre: genre.presence,
            genre_other: genre_other.presence,
            smoking_area: smoking_area,
            smoking_type: smoking_type,
            tabelog_url: tabelog_url.presence,
            tabelog_affiliate_url: tabelog_affiliate_url.presence,
            hotpepper_url: hotpepper_url.presence,
            last_confirmed_on: last_confirmed_on,
            smoking_unverified: true
          )

          if shop.opening_hours_text.blank? && shop.respond_to?(:derived_opening_hours_text, true)
            derived_text = shop.send(:derived_opening_hours_text)
            shop.opening_hours_text = derived_text if derived_text.present?
          end

          if shop.closed_days_text.blank? && shop.respond_to?(:derived_closed_days_text, true)
            derived_closed = shop.send(:derived_closed_days_text)
            shop.closed_days_text = derived_closed if derived_closed.present?
          end

          shop.approved = false
          shop.rejected = false if shop.respond_to?(:rejected=)
          shop.smoking_unverified = true if shop.respond_to?(:smoking_unverified=)

          shop.save!
          success += 1
        rescue => e
          failed += 1

          detail =
            if e.respond_to?(:record) && e.record.present?
              e.record.errors.full_messages.join(", ")
            else
              e.message
            end

          debug_fields = row.fields.first(12).map.with_index { |v, i| "#{i}=#{v.inspect}" }.join(" | ")

          message = "#{idx + 2}行目: #{e.class} - #{detail} / 読取 name=#{name.inspect} genre=#{genre.inspect} address=#{address.inspect} phone=#{phone.inspect} / fields=#{debug_fields}"
          error_messages << message
          Rails.logger.error(
            "[CSV IMPORT ERROR] #{message} row=#{row.to_h.inspect} raw_genre=#{raw_genre_value.inspect} normalized_genre=#{genre.inspect}"
          )
        end
      end

      if processed_rows.zero?
        return redirect_to admin_shops_path,
                           flash: { admin_alert: "CSVのデータ行を処理できませんでした。ヘッダ名・文字コード・保存形式を確認してください。" }
      end

      notice_message = "CSV取込完了：#{success}件成功 / #{failed}件失敗 / 重複#{skipped_duplicates}件スキップ / 空行#{skipped_blank}件スキップ / 対象#{processed_rows}件"
      flash_payload = { admin_notice: notice_message }
      admin_error_message = error_messages.first(5).join(" / ").presence
      flash_payload[:admin_alert] = admin_error_message if admin_error_message.present?

      redirect_to admin_shops_path, flash: flash_payload
    rescue CSV::MalformedCSVError => e
      redirect_to admin_shops_path, flash: { admin_alert: "CSV形式が不正です: #{e.message}" }
    rescue => e
      redirect_to admin_shops_path, flash: { admin_alert: "インポート中にエラーが発生しました: #{e.class} - #{e.message}" }
    end
  end

  private

  VALUECOMMERCE_SID = "3769275"
  VALUECOMMERCE_PID = "892611116"

  def build_tabelog_affiliate_url(url)
    raw_url = url.to_s.strip
    return nil if raw_url.blank?
    return raw_url if raw_url.include?("ck.jp.ap.valuecommerce.com/servlet/referral")
    return raw_url if raw_url.include?("not-found.local")
    return raw_url unless raw_url.include?("tabelog.com/")

    "https://ck.jp.ap.valuecommerce.com/servlet/referral?sid=#{VALUECOMMERCE_SID}&pid=#{VALUECOMMERCE_PID}&vc_url=#{CGI.escape(raw_url)}"
  end

  def duplicate_exists_against_approved_shops?(shop)
    duplicate_scope_for_approved_shops(shop).exists?
  end

  def duplicate_scope_for_approved_shops(shop)
    scope = Shop.where(approved: true).where.not(id: shop.id)

    conditions = []
    binds = {}

    # 電話番号だけの一致では承認を止めない。
    # 系列店・同一受付番号の別店舗があるため、電話番号一致は警告表示に留める。

    if shop.name.present? && shop.address.present?
      conditions << "(name = :name AND address = :address)"
      binds[:name] = shop.name
      binds[:address] = shop.address
    end

    return Shop.none if conditions.empty?

    scope.where(conditions.join(" OR "), binds)
  end

  def build_duplicate_states_for(shops)
    return {} if shops.blank?

    states = Hash.new(:none)
    ids = shops.map(&:id)

    scope = Shop.where.not(id: ids)

    place_id_available = Shop.column_names.include?("place_id")

    place_ids =
      if place_id_available
        shops.filter_map do |shop|
          shop.respond_to?(:place_id) ? shop.place_id.presence : nil
        end.uniq
      else
        []
      end

    normalized_phones = shops.map { |shop| shop.normalized_phone.presence }.compact.uniq
    names = shops.map { |shop| shop.name.presence }.compact.uniq
    addresses = shops.map { |shop| shop.address.presence }.compact.uniq

    grouped = {}

    if place_id_available && place_ids.present?
      scope.where(place_id: place_ids).pluck(:id, :place_id, :approved, :rejected).each do |candidate_id, place_id, approved, rejected|
        grouped[[:place_id, place_id]] ||= []
        grouped[[:place_id, place_id]] << [candidate_id, approved, rejected]
      end
    end

    if normalized_phones.present?
      scope.where(normalized_phone: normalized_phones).pluck(:id, :normalized_phone, :approved, :rejected).each do |candidate_id, normalized_phone, approved, rejected|
        grouped[[:normalized_phone, normalized_phone]] ||= []
        grouped[[:normalized_phone, normalized_phone]] << [candidate_id, approved, rejected]
      end
    end

    if names.present?
      scope.where(name: names).pluck(:id, :name, :approved, :rejected).each do |candidate_id, name, approved, rejected|
        grouped[[:name, name]] ||= []
        grouped[[:name, name]] << [candidate_id, approved, rejected]
      end
    end

    if addresses.present?
      scope.where(address: addresses).pluck(:id, :address, :approved, :rejected).each do |candidate_id, address, approved, rejected|
        grouped[[:address, address]] ||= []
        grouped[[:address, address]] << [candidate_id, approved, rejected]
      end
    end

    shops.each do |shop|
      candidates = []

      if place_id_available && shop.respond_to?(:place_id) && shop.place_id.present?
        candidates.concat(grouped[[:place_id, shop.place_id]] || [])
      end

      if shop.normalized_phone.present?
        candidates.concat(grouped[[:normalized_phone, shop.normalized_phone]] || [])
      end

      if shop.name.present?
        candidates.concat(grouped[[:name, shop.name]] || [])
      end

      if shop.address.present?
        candidates.concat(grouped[[:address, shop.address]] || [])
      end

      states[shop.id] =
        if candidates.any? { |_, approved, rejected| approved || rejected }
          :approved_or_rejected
        elsif candidates.any?
          :pending_only
        else
          :none
        end
    end

    states
  end

  def normalize_admin_shop_defaults!(shop)
    shop.last_confirmed_on ||= Date.current if shop.respond_to?(:last_confirmed_on)

    if shop.respond_to?(:approved=) && shop.approved.nil?
      shop.approved = false
    end

    if shop.respond_to?(:rejected=) && shop.rejected.nil?
      shop.rejected = false
    end

    if shop.respond_to?(:on_hold=) && shop.on_hold.nil?
      shop.on_hold = false
    end

    if shop.respond_to?(:smoking_unverified=) && shop.smoking_unverified.nil?
      shop.smoking_unverified = true
    end
  end

  def populate_derived_hours_fields!(shop)
    if shop.opening_hours_text.blank? && shop.respond_to?(:derived_opening_hours_text, true)
      derived_text = shop.send(:derived_opening_hours_text)
      shop.opening_hours_text = derived_text if derived_text.present?
    end

    if shop.closed_days_text.blank? && shop.respond_to?(:derived_closed_days_text, true)
      derived_closed = shop.send(:derived_closed_days_text)
      shop.closed_days_text = derived_closed if derived_closed.present?
    end
  end

    def shop_params
    params.require(:shop).permit(
      :name,
      :address,
      :area,
      :nearest_station,
      :phone,
      :genre,
      :genre_other,
      :note,
      :public_store_details,
      :smoking_area,
      :smoking_type,
      :smoking_unverified,
      :smoking_hours_text,
      :last_confirmed_on,
      :opening_hours_text,
      :holiday_hours_text,
      :closed_days_text,
      :special_hours_note,
      :budget_range,
      :last_order_text,
      :private_room_type,
      :all_you_can_drink_type,
      :raw_import_text,
      :import_source,
      :imported_at,
      :tabelog_url,
      :tabelog_affiliate_url,
      :tabelog_match_method,
      :tabelog_candidate_url,
      :tabelog_candidate_affiliate_url,
      :tabelog_candidate_method,
      :hotpepper_url,
      :custom_affiliate_url,
      :custom_affiliate_label,
      :thumbnail_kind,
      :thumbnail_index,
      seat_type_tags: [],
      import_metadata: {},
      opening_hours_json: {}
    )
  end

  def photo_params
    params.require(:shop).permit(
      food_photos: [],
      interior_photos: [],
      exterior_photos: [],
      menu_photos: []
    )
  end

  def purge_removed_photos!(shop)
    {
      food_photos: params[:remove_food_photos_ids],
      interior_photos: params[:remove_interior_photos_ids],
      exterior_photos: params[:remove_exterior_photos_ids],
      menu_photos: params[:remove_menu_photos_ids]
    }.each do |field, ids|
      ids = Array(ids).map(&:to_s)
      next if ids.blank?

      shop.public_send(field).attachments.each do |attachment|
        attachment.purge_later if ids.include?(attachment.id.to_s)
      end
    end
  end

  def attach_uploaded_photos!(shop)
    photos = photo_params

    photos[:food_photos].reject(&:blank?).each do |photo|
      shop.food_photos.attach(photo)
    end if photos[:food_photos].present?

    photos[:interior_photos].reject(&:blank?).each do |photo|
      shop.interior_photos.attach(photo)
    end if photos[:interior_photos].present?

    photos[:exterior_photos].reject(&:blank?).each do |photo|
      shop.exterior_photos.attach(photo)
    end if photos[:exterior_photos].present?

    photos[:menu_photos].reject(&:blank?).each do |photo|
      shop.menu_photos.attach(photo)
    end if photos[:menu_photos].present?
  end
end