  def approve
    submission = ShopVerificationSubmission.find(params[:id])
    shop = submission.shop

    attrs = {}

    if submission.smoking_location == "no_smoking"
      attrs[:approved] = false if shop.has_attribute?(:approved)
      attrs[:on_hold] = true if shop.has_attribute?(:on_hold)
      attrs[:smoking_unverified] = false if shop.has_attribute?(:smoking_unverified)
    elsif submission.smoking_location == "seat_smoking"
      attrs[:smoking_type] = "all_smoking" if shop.has_attribute?(:smoking_type)
      attrs[:smoking_unverified] = false if shop.has_attribute?(:smoking_unverified)
    elsif submission.smoking_location == "smoking_area_only"
      attrs[:smoking_type] = "separated" if shop.has_attribute?(:smoking_type)
      attrs[:smoking_unverified] = false if shop.has_attribute?(:smoking_unverified)
    end

    if shop.has_attribute?(:smoking_note)
      note = shop.smoking_note.to_s
      new_note = "[電話確認] #{submission.smoking_location_label} / #{submission.tobacco_type_label}"
      new_note += " / #{submission.memo}" if submission.memo.present?
      attrs[:smoking_note] = [note, new_note].reject(&:blank?).join("\n")
    end

    shop.update!(attrs) if attrs.present?

    submission.update!(
      status: "approved",
      reviewed_by_id: current_admin_user_id,
      reviewed_at: Time.current
    )

    redirect_to admin_shop_verification_submissions_path, notice: "承認しました"
  end