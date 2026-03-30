# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/app/controllers/admin/contact_messages_controller.rb
class Admin::ContactMessagesController < Admin::BaseController
before_action :set_contact_message, only: [:show, :destroy]

def index
@contact_messages = ContactMessage.order(created_at: :desc).to_a
end

def show
end

def destroy
@contact_message.destroy!
redirect_to admin_contact_messages_path, notice: "削除しました"
end

private

def set_contact_message
@contact_message = ContactMessage.find(params[:id])
end
end