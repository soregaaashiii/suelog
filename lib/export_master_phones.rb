# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/lib/export_master_phones.rb
# frozen_string_literal: true

require "csv"
require "fileutils"

module ExportMasterPhones
module_function

DEFAULT_OUTPUT_PATH = Rails.root.join("tmp", "master_phones.csv").to_s

def run(output_path: DEFAULT_OUTPUT_PATH)
phones =
if Shop.column_names.include?("normalized_phone")
Shop.where.not(normalized_phone: [nil, ""]).pluck(:normalized_phone)
else
Shop.where.not(phone: [nil, ""]).pluck(:phone).map { |v| v.to_s.gsub(/\D/, "") }
end

phones = phones.map { |v| v.to_s.gsub(/\D/, "") }.reject(&:empty?).uniq.sort

FileUtils.mkdir_p(File.dirname(output_path))

CSV.open(output_path, "w") do |csv|
csv << ["normalized_phone"]
phones.each do |phone|
csv << [phone]
end
end

puts "exported: #{phones.size} phones"
puts "output: #{output_path}"
true
end
end

if __FILE__ == $PROGRAM_NAME
require_relative "../config/environment"

output_path = ARGV[0].presence || ExportMasterPhones::DEFAULT_OUTPUT_PATH
success = ExportMasterPhones.run(output_path: output_path)
exit(success ? 0 : 1)
end