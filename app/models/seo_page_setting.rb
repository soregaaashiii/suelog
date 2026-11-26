# frozen_string_literal: true

class SeoPageSetting < ApplicationRecord
  has_many :revisions, class_name: "SeoPageRevision", dependent: :delete_all
  attr_readonly :path
  before_validation :normalize_metadata
  validates :path, presence: true, uniqueness: true
  validates :title, length: { maximum: 200 }
  validates :description, length: { maximum: 500 }
  validate :known_page

  def customized? = title.present? || description.present?
  def version_token = persisted? ? lock_version.to_s : "new"

  def effective(defaults)
    { title: title.presence || defaults.fetch(:title), description: description.presence || defaults.fetch(:description) }
  end

  def snapshot(defaults)
    { "title" => title, "description" => description,
      "effective_title" => effective(defaults).fetch(:title), "effective_description" => effective(defaults).fetch(:description) }
  end

  private

  def normalize_metadata
    self.title = title.to_s.squish.presence
    self.description = description.to_s.squish.presence
  end

  def known_page
    errors.add(:path, "はSEOページ一覧のURLを指定してください") unless GeographicPageMetadata.definition(path)
  end
end
