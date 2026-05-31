class ShopVerificationSubmission < ApplicationRecord
  belongs_to :shop
  belongs_to :sub_admin_user

  SMOKING_LOCATIONS = {
    "seat_smoking" => "席で吸える",
    "smoking_area_only" => "喫煙所あり",
    "no_smoking" => "吸えない",
    "unknown" => "不明",
    "no_answer" => "電話出ず"
  }.freeze

  TOBACCO_TYPES = {
    "both" => "紙・加熱式どちらも可",
    "heated_only" => "加熱式のみ",
    "paper_only" => "紙タバコのみ",
    "unknown" => "不明"
  }.freeze

  validates :smoking_location, presence: true, inclusion: { in: SMOKING_LOCATIONS.keys }
  validates :tobacco_type, presence: true, inclusion: { in: TOBACCO_TYPES.keys }

  scope :pending, -> { where(status: "pending").order(created_at: :desc) }

  def smoking_location_label
    SMOKING_LOCATIONS[smoking_location] || smoking_location
  end

  def tobacco_type_label
    TOBACCO_TYPES[tobacco_type] || tobacco_type
  end
end