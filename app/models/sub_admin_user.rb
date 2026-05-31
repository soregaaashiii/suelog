class SubAdminUser < ApplicationRecord
  has_secure_password

  has_many :shop_verification_submissions, dependent: :nullify

  PERMISSIONS = {
    "shops_read" => "店舗を見る",
    "shops_edit" => "店舗を編集する",
    "shops_approve" => "店舗を承認する",
    "shops_reject" => "店舗を却下する",
    "smoking_check" => "電話確認をする",
    "phone_check_hold" => "電話確認保留を操作する",
    "articles_read" => "記事を見る",
    "articles_edit" => "記事を編集する",
    "reports_read" => "通報を見る",
    "reports_resolve" => "通報を処理する",
    "analytics_read" => "分析を見る",
    "csv_export" => "CSV出力",
    "sub_admin_manage" => "サブ管理者を管理する"
  }.freeze

  validates :name, presence: true
  validates :login_id, presence: true, uniqueness: true
  validates :permissions, presence: true, allow_blank: true

  scope :active, -> { where(active: true) }

  def can?(permission)
    Array(permissions).include?(permission.to_s)
  end
end