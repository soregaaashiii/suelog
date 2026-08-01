# frozen_string_literal: true

require Rails.root.join("lib/shop_registration_slow_request_diagnostics")

Rails.application.config.middleware.insert_before(
  0,
  ShopRegistrationSlowRequestDiagnostics::Middleware
)

Rails.application.config.after_initialize do
  ShopRegistrationSlowRequestDiagnostics.install!
end
