class HotpepperApiBatch < ApplicationRecord
  has_many :targets, class_name: "HotpepperApiTarget", dependent: :destroy
  def shop_first? = matching_basis == "shop"
  has_many :rows, class_name: "HotpepperApiRow", dependent: :destroy
  has_many :executions, class_name: "HotpepperApiExecution", dependent: :destroy
  has_many :events, class_name: "HotpepperApiEvent", dependent: :destroy
  scope :metadata, -> { select(column_names - [ "source_bytes" ]) }
end
