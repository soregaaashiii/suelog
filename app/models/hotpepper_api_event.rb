class HotpepperApiEvent < ApplicationRecord
  belongs_to :hotpepper_api_batch
  serialize :payload, coder: JSON
end
