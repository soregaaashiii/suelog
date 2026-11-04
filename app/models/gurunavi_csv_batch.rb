class GurunaviCsvBatch < ApplicationRecord
  has_many :targets, class_name: "GurunaviCsvTarget", dependent: :destroy
  def shop_first? = matching_basis == "shop"
  has_many :rows, class_name: "GurunaviCsvRow", dependent: :destroy
  has_many :executions, class_name: "GurunaviCsvExecution", dependent: :destroy
  has_many :events, class_name: "GurunaviCsvEvent", dependent: :destroy
  scope :metadata, -> { select(column_names - [ "source_bytes" ]) }
end
