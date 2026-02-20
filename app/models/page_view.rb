class PageView < ApplicationRecord
  belongs_to :shop, optional: true

  # 重くならない範囲で最低限
  validates :path, presence: true
end
