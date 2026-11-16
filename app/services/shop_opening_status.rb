# frozen_string_literal: true

# One evaluator per request. Identical schedules have identical opening status;
# keep the existing Shop predicate (including its holiday and overnight rules).
class ShopOpeningStatus
  COLUMNS = %w[opening_hours_json opening_hours_text holiday_hours_text].freeze

  def initialize
    @statuses = {}
  end

  def for_shop(shop)
    key = COLUMNS.map { |column| shop.public_send(column) }
    @statuses.fetch(key) { @statuses[key] = shop.open_now? }
  end

  def for_row(row)
    key = COLUMNS.map { |column| row[column] }
    @statuses.fetch(key) do
      @statuses[key] = Shop.instantiate(row.slice(*COLUMNS)).open_now?
    end
  end
end
