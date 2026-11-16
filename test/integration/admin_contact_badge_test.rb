require "test_helper"

class AdminContactBadgeTest < ActionDispatch::IntegrationTest
  test "admin navigation shows all saved contacts and reflects creation and deletion" do
    ContactMessage.delete_all
    get admin_contact_messages_path, headers: admin_headers
    assert_response :success
    assert_select "a[href='#{admin_contact_messages_path}'] .admin-badge.is-zero", text: "0"

    first = ContactMessage.create!(name: "確認者", email: "test@example.com", subject: "確認1", body: "お問い合わせ本文")
    second = ContactMessage.create!(name: "確認者", email: "test@example.com", subject: "確認2", body: "お問い合わせ本文")
    get admin_articles_path, headers: admin_headers
    assert_response :success
    assert_select "a[href='#{admin_contact_messages_path}'] .admin-badge:not(.is-zero)", text: "2"

    # Viewing a message does not remove it from the total saved count.
    get admin_contact_message_path(first), headers: admin_headers
    assert_response :success
    assert_select "a[href='#{admin_contact_messages_path}'] .admin-badge", text: "2"

    delete admin_contact_message_path(second), headers: admin_headers
    assert_redirected_to admin_contact_messages_path
    get admin_contact_messages_path, headers: admin_headers
    assert_response :success
    assert_select "a[href='#{admin_contact_messages_path}'] .admin-badge", text: "1"
  end

  private

  def admin_headers
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name: "([^"]+)", password: "([^"]+)"/)
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
  end
end
