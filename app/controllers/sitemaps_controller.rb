# frozen_string_literal: true

class SitemapsController < ApplicationController
def show
xml_path = Rails.root.join("public", "sitemap.xml")
gz_path = Rails.root.join("public", "sitemap.xml.gz")

if File.exist?(xml_path)
send_file xml_path,
type: "application/xml",
disposition: "inline"
elsif File.exist?(gz_path)
send_file gz_path,
type: "application/gzip",
disposition: "inline"
else
head :not_found
end
end
end