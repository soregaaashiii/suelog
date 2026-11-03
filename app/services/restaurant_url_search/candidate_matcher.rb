module RestaurantUrlSearch
  class CandidateMatcher
    def self.call(shop, evidence)
      n = Normalization
      return [false, "店舗詳細情報を取得できません"] unless evidence.is_a?(Hash)
      return [false, "閉店・移転情報があり要確認"] if evidence[:relocated]
      return [false, "店名・支店名が一致しません"] unless n.name(shop.name).present? && n.name(shop.name) == n.name(evidence[:name])
      return [false, "住所が不足または一致しません（建物・階数も確認）"] unless n.address(shop.address).match?(/\d/) && n.address(shop.address) == n.address(evidence[:address])
      expected_phone = n.phone(shop.phone)
      actual_phone = n.phone(evidence[:phone])
      if expected_phone.present? && (actual_phone.blank? || expected_phone != actual_phone)
        return [false, "電話番号が不足または一致しません"]
      end
      [true, expected_phone.present? ? "店名・支店名・住所・電話番号一致" : "店名・支店名・住所一致（登録電話なし）"]
    end
  end
end
