require "json"

class AddAffiliateExcludedAt < ActiveRecord::Migration[8.1]
  def change
    %w[gurunavi_csv hotpepper_api].each do |prefix|
      add_column "#{prefix}_targets", :excluded_at, :datetime
      reversible do |dir|
        dir.up do
          targets = Class.new(ActiveRecord::Base) { self.table_name = "#{prefix}_targets" }
          events = Class.new(ActiveRecord::Base) { self.table_name = "#{prefix}_events" }
          targets.reset_column_information
          times = {}
          events.where(action: "exclude").order(:id).pluck(:payload, :created_at).each do |payload, time|
            target_id = JSON.parse(payload.to_s)["target_id"]
            times[target_id.to_i] = time if target_id
          end
          targets.where(state: "excluded").select(:id, :updated_at).find_in_batches(batch_size: 500) do |group|
            cases = group.map do |target|
              value = connection.quote(times[target.id] || target.updated_at)
              value = "CAST(#{value} AS timestamp)" if connection.adapter_name == "PostgreSQL"
              "WHEN #{target.id.to_i} THEN #{value}"
            end
            execute "UPDATE #{prefix}_targets SET excluded_at = CASE id #{cases.join(' ')} END WHERE id IN (#{group.map(&:id).join(',')})"
          end
        end
      end
    end
  end
end
