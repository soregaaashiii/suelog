# frozen_string_literal: true

namespace :aicoo do
  desc "Diagnose Suelog Shop/Article callbacks and Activity API delivery"
  task diagnose_suelog_activity_api: :environment do
    Aicoo::SuelogActivityApiDiagnostic.call(send_probe: ENV["SEND"] == "1")
  end
end
