module ShopImagesHelper
  SHOP_FALLBACK_IMAGES = {
    "居酒屋" => "yakitori.jpg",
    "バー・パブ" => "bar.jpg",
    "ラウンジ" => "lounge.jpg",
    "スナック" => "snack.jpg",
    "カフェ" => "cafe.jpg",
    "喫茶店" => "cafe.jpg",
    "焼肉" => "yakiniku.jpg",
    "バーベキュー" => "yakiniku.jpg",
    "寿司" => "sushi.jpg",
    "和食" => "washoku.jpg",
    "海鮮" => "sushi.jpg",
    "中華" => "chinese.jpg",
    "韓国料理" => "korean.jpg",
    "エスニック" => "ethnic.jpg",
    "洋食" => "western.jpg",
    "レストラン" => "western.jpg",
    "フレンチ" => "french.jpg",
    "イタリアン" => "italian.jpg",
    "アメリカ料理" => "american.jpg",
    "ステーキ" => "steak.jpg",
    "ラーメン" => "ramen.jpg",
    "串カツ" => "kushikatsu.jpg",
    "たこ焼き" => "takoyaki.jpg",
    "お好み焼き" => "okonomiyaki.jpg",
    "天ぷら" => "tempura.jpg"
  }.freeze

  def shop_fallback_image_path(shop)
    "fallbacks/#{SHOP_FALLBACK_IMAGES.fetch(shop.display_genre, "other.jpg")}"
  end

  def shop_card_image(shop, **options)
    photo = shop.thumbnail_attachment
    source = photo.present? ? (photo.variable? ? photo.variant(resize_to_limit: [240, 240]) : photo) : shop_fallback_image_path(shop)
    image_tag(source, **{ alt: shop.name, loading: "lazy", decoding: "async" }.merge(options))
  end
end
