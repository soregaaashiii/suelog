# /app/controllers/shop_edit_requests_controller.rb
class ShopEditRequestsController < ApplicationController

  def new
    @shop = Shop.find(params[:shop_id])

    @req = @shop.shop_edit_requests.build(
      proposed_name: @shop.name,
      proposed_address: @shop.address,
      proposed_nearest_station: @shop.nearest_station,
      proposed_phone: @shop.phone,
      proposed_opening_hours: @shop.opening_hours,
      proposed_opening_hours_data: @shop.opening_hours_data_for_form,
      proposed_smoking_area: @shop.smoking_area,
      proposed_smoking_type: @shop.smoking_type,
      genre: @shop.genre,
      genre_other: @shop.genre_other,
      proposed_thumbnail_kind: (@shop.thumbnail_kind.presence || "auto"),
      proposed_thumbnail_index: (@shop.thumbnail_index.presence || 1),
      note: @shop.note
    )
  end


  def create
    @shop = Shop.find(params[:shop_id])

    @req = @shop.shop_edit_requests.build(
      proposed_name: @shop.name,
      proposed_address: @shop.address,
      proposed_nearest_station: @shop.nearest_station,
      proposed_phone: @shop.phone,
      proposed_opening_hours: @shop.opening_hours,
      proposed_opening_hours_data: @shop.opening_hours_data_for_form,
      proposed_smoking_area: @shop.smoking_area,
      proposed_smoking_type: @shop.smoking_type,
      genre: @shop.genre,
      genre_other: @shop.genre_other,
      proposed_thumbnail_kind: (@shop.thumbnail_kind.presence || "auto"),
      proposed_thumbnail_index: (@shop.thumbnail_index.presence || 1),
      note: @shop.note
    )

    @req.assign_attributes(req_params)
    @req.status = :pending if @req.respond_to?(:status)

    # ==============================
    # 空入力は現状維持
    # ==============================

    @req.proposed_name = @shop.name if blankish?(@req.proposed_name)
    @req.proposed_address = @shop.address if blankish?(@req.proposed_address)
    @req.proposed_nearest_station = @shop.nearest_station if blankish?(@req.proposed_nearest_station)
    @req.proposed_phone = @shop.phone if blankish?(@req.proposed_phone)
    @req.proposed_opening_hours = @shop.opening_hours if blankish?(@req.proposed_opening_hours)

    if @req.proposed_opening_hours_data.blank?
      @req.proposed_opening_hours_data = @shop.opening_hours_data_for_form
    end

    @req.proposed_smoking_area = @shop.smoking_area if blankish?(@req.proposed_smoking_area)
    @req.proposed_smoking_type = @shop.smoking_type if blankish?(@req.proposed_smoking_type)

    if blankish?(@req.genre)
      @req.genre = @shop.genre
      @req.genre_other = @shop.genre_other
    end

    if @req.genre.to_s != "その他" && blankish?(@req.genre_other)
      @req.genre_other = @shop.genre_other
    end

    if @req.respond_to?(:proposed_last_confirmed_on) && @req.proposed_last_confirmed_on.blank?
      @req.proposed_last_confirmed_on = nil
    end

    @req.note = @shop.note if blankish?(@req.note)

    if blankish?(@req.proposed_thumbnail_kind)
      @req.proposed_thumbnail_kind = (@shop.thumbnail_kind.presence || "auto")
    end

    if @req.proposed_thumbnail_index.blank? || @req.proposed_thumbnail_index.to_i <= 0
      @req.proposed_thumbnail_index = (@shop.thumbnail_index.presence || 1)
    end

    if @req.save
      increment_contribution!
      redirect_to done_shop_shop_edit_requests_path(@shop),
                  notice: contribution_message
    else
      render :new, status: :unprocessable_entity
    end
  end


  def done
    @shop = Shop.find(params[:shop_id])
  end


  private

  def req_params
    params.require(:shop_edit_request).permit(
      :proposer_name, :note,
      :proposed_name, :proposed_address, :proposed_last_confirmed_on,
      :proposed_nearest_station, :proposed_phone,
      :proposed_smoking_area, :proposed_smoking_type,
      :proposed_area,
      :genre, :genre_other,
      :proposed_opening_hours,
      :proposed_thumbnail_kind, :proposed_thumbnail_index,
      proposed_opening_hours_data: {},
      food_photos: [],
      interior_photos: [],
      exterior_photos: [],
      menu_photos: []
    )
  end


  def blankish?(v)
    v.nil? || v.to_s.strip == ""
  end


  # ==============================
  # 🔥 協力回数カウント
  # ==============================

  def increment_contribution!
    session[:contribution_count] ||= 0
    session[:contribution_count] += 1
  end


  # ==============================
  # 🔥 バッジ＆100倍数演出
  # ==============================

  def contribution_message
    count = session[:contribution_count]
    badge = view_context.contribution_badge(count)

    # 🔥 100の倍数
    if count % 100 == 0
      return "🔥 #{count}回達成！超ご協力ありがとうございます！！"
    end

    # 🔥 バッジ達成タイミング
    case count
    when 1, 5, 10, 30, 100
      return "🎉 #{badge[:name]}バッジ獲得！ありがとうございます！"
    else
      return "ご協力ありがとうございます！"
    end
  end

end