# frozen_string_literal: true

# One generator for the public pages and their admin defaults.
class GeographicPageMetadata
  def self.definition(path)
    match = path.to_s.match(%r{\A/(areas|stations)/([a-z0-9-]+)(?:/(genre|smoking)/([a-z0-9-]+))?\z})
    return unless match
    directory = GeographicDirectory.new
    entry = directory.definition(match[1] == "areas" ? "region" : "station", match[2])
    return unless entry
    facet = GeographicFacets.new(directory).definition(match[3], match[4]) if match[3]
    return if match[3] && !facet
    { entry: entry, facet: facet }
  end

  def self.generated(entry:, facet:, count:)
    context = entry.fetch("kind") == "station" ? "#{entry.fetch('label')}周辺" : entry.fetch("label")
    heading = if facet
      facet.fetch("kind") == "genre" ? "#{context}で喫煙できる#{facet.fetch('label')}" : "#{context}の#{facet.fetch('label')}の店"
    else
      "#{context}で喫煙できる店"
    end
    description = if facet
      "#{heading}を掲載。#{count}件の営業時間・地図・喫煙条件を確認できます。喫煙できる曜日・時間・席やたばこの種類は店舗により異なります。来店前に各店舗の詳細をご確認ください。"
    else
      "#{context}の掲載店舗#{count}件から探せます。喫煙条件・確認状況・営業時間・地図を確認し、席で喫煙可や加熱式のみなどで絞り込めます。"
    end
    { heading: heading, title: "#{heading}｜吸えログ", description: description }
  end
end
