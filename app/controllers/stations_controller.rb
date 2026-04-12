class StationsController < ApplicationController
  def show
    @station = params[:station]

    @shops = Shop
      .where(approved: true)
      .where("nearest_station LIKE ?", "%#{@station}%")
      .order(created_at: :desc)
      .page(params[:page])
      .per(params[:per] || 30)

    @page_title = "#{@station}で喫煙できる店｜吸えログ"
    @page_description = "#{@station}周辺で喫煙可能な飲食店を掲載。席で吸える・喫煙所ありなどの情報をまとめています。"
  end
end

