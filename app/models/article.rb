# /Users/kawamuratakuya/dev/suelog/app/models/article.rb
class Article < ApplicationRecord
  has_rich_text :body
  has_one_attached :eyecatch

  before_validation :set_slug

  scope :published, -> {
    where(published: true)
      .where("published_at IS NULL OR published_at <= ?", Time.current)
      .order(published_at: :desc, created_at: :desc)
  }

  scope :recommended_for, ->(area_key) {
    where("recommended_areas LIKE ?", "%#{area_key}%")
      .order(recommended_order: :asc, published_at: :desc, created_at: :desc)
  }

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :summary, length: { maximum: 300 }, allow_blank: true
  validates :seo_title, length: { maximum: 70 }, allow_blank: true
  validates :meta_description, length: { maximum: 160 }, allow_blank: true

  def to_param
    slug
  end

  def publishable?
    published? && (published_at.blank? || published_at <= Time.current)
  end

  def recommended_area_list
    recommended_areas.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def recommended_area_list=(values)
    self.recommended_areas = Array(values).reject(&:blank?).join(",")
  end

  private

  def set_slug
    base = slug.presence || title.to_s
    self.slug = base.to_s.parameterize if base.present?
  end
end