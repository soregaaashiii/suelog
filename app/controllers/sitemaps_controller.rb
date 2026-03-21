# frozen_string_literal: true

class SitemapsController < ApplicationController
def show
sitemap_path = Rails.root.join("public", "sitemap.xml")

if File.exist?(sitemap_path)
send_file sitemap_path,
type: "application/xml; charset=utf-8",
disposition: "inline"
else
render plain: "sitemap not found", status: :not_found
end
end
end