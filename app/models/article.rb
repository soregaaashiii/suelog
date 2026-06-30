# /Users/kawamuratakuya/dev/suelog/app/models/article.rb
class Article < ApplicationRecord
  has_rich_text :body
  has_one_attached :eyecatch

  before_validation :set_slug
  after_commit :log_aicoo_article_created, on: :create
  after_commit :log_aicoo_article_updated, on: :update
  after_commit :log_aicoo_article_destroyed, on: :destroy

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

  def log_aicoo_article_created
    log_aicoo_article_activity("article_created", "記事を追加")
  end

  def log_aicoo_article_updated
    changed_fields = previous_changes.except("updated_at")
    return if changed_fields.blank?

    activity_type = if changed_fields.key?("published") && published?
      "article_published"
    elsif (changed_fields.keys & %w[seo_title meta_description slug]).any?
      "article_seo_updated"
    else
      "article_updated"
    end
    title_prefix = {
      "article_published" => "記事を公開",
      "article_seo_updated" => "記事SEOを更新"
    }.fetch(activity_type, "記事を更新")
    log_aicoo_article_activity(activity_type, title_prefix)
  end

  def log_aicoo_article_destroyed
    log_aicoo_article_activity("article_deleted", "記事を削除")
  end

  def log_aicoo_article_activity(activity_type, title_prefix)
    AicooActivityLogger.log(
      business_key: "suelog",
      activity_type:,
      source_type: "article",
      source_id: id,
      title: "#{title_prefix}: #{title}",
      summary: "#{title} の記事情報を変更しました",
      occurred_at: Time.current.iso8601,
      metadata: {
        slug: slug,
        area: recommended_area_list.first,
        recommended_areas: recommended_area_list,
        target_keyword: seo_title.presence || title,
        published: published,
        changed_fields: previous_changes.except("updated_at").keys
      }.compact
    )
  end
end
