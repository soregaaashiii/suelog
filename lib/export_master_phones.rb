# frozen_string_literal: true

require "csv"

output_path = "/Users/kawamuratakuya/dev/suelog_collector/out/master_phones.csv"

phones =
if Shop.column_names.include?("normalized_phone")
Shop.where.not(normalized_phone: [nil, ""]).pluck(:normalized_phone)
else
Shop.where.not(phone: [nil, ""]).pluck(:phone).map { |v| v.to_s.gsub(/\D/, "") }
end

phones = phones.map { |v| v.to_s.gsub(/\D/, "") }.reject(&:empty?).uniq.sort

CSV.open(output_path, "w") do |csv|
csv << ["normalized_phone"]
phones.each do |phone|
csv << [phone]
end
end

puts "exported: #{phones.size} phones"