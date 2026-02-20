class ReviewReport < ApplicationRecord
belongs_to :review

enum :status, { pending: 0, resolved: 1, rejected: 2 }

validates :reason, presence: true
end
