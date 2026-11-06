module Admin::AffiliateRegistrationHelper
  def affiliate_registration_path(prefix, action = nil, **params)
    raise ArgumentError, "対応していない登録先です" unless %w[gurunavi_csv hotpepper_api].include?(prefix)
    helper = [ action, "admin", prefix, "batch_path" ].compact.join("_")
    public_send(helper, @batch, **params)
  end
end
