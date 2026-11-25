# frozen_string_literal: true

# XML endpoints deliberately bypass HTML browser checks and importmap ETags.
class SitemapsController < ActionController::Base

  def index
    render_sitemap PublicSitemap.new.index
  end

  def pages
    render_sitemap PublicSitemap.new.pages
  end

  def records
    xml = PublicSitemap.new.records(params[:kind], params[:bucket].to_i)
    return head :not_found if xml.nil?

    render_sitemap xml
  end

  private

  def render_sitemap(xml)
    expires_in PublicSitemap::CACHE_TTL, public: true
    render body: xml, content_type: "application/xml; charset=utf-8"
  end
end
