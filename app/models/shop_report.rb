class ShopReport < ApplicationRecord
  belongs_to :shop

  NON_SMOKING_REASONS = {
    "禁煙になった" => "became_non_smoking",
    "禁煙店になった" => "became_non_smoking",
    "禁煙店だった" => "was_non_smoking"
  }.freeze

  def non_smoking_hold_reason
    NON_SMOKING_REASONS[reason.to_s]
  end

  enum :status, { pending: 0, resolved: 1, rejected: 2 }
end
