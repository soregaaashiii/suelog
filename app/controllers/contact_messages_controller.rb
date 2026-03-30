# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/app/controllers/contact_messages_controller.rb
class ContactMessagesController < ApplicationController
def new
@contact_message = ContactMessage.new
end

def create
@contact_message = ContactMessage.new(contact_message_params)

if @contact_message.save
redirect_to done_contact_messages_path
else
render :new, status: :unprocessable_entity
end
end

def done
end

private

def contact_message_params
params.require(:contact_message)
.permit(:name, :email, :subject, :body)
end
end