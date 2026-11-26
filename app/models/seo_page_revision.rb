# frozen_string_literal: true

class SeoPageRevision < ApplicationRecord
  belongs_to :seo_page_setting
  validates :change_note, length: { maximum: 500 }
end
