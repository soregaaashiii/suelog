class GurunaviCsvEvent < ApplicationRecord
  belongs_to :gurunavi_csv_batch
  serialize :payload, coder: JSON
end
