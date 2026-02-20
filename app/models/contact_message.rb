# app/models/contact_message.rb
class ContactMessage < ApplicationRecord
  validates :name, presence: { message: "を入力してください" }, length: { maximum: 50 }
  validates :email, presence: { message: "を入力してください" }, length: { maximum: 255 },
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: "の形式が正しくありません" }
  validates :subject, presence: { message: "を入力してください" }, length: { maximum: 100 }
  validates :body, presence: { message: "を入力してください" }, length: { maximum: 5000 }
end

