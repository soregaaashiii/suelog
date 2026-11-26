# frozen_string_literal: true

# Uses the existing cached scalar snapshot; never loads shops or queries per link.
class GeographicPageGuide
  CONDITIONS = {
    "seat-smoking" => "席・フロア・時間が限定される場合があります。どの席で吸えるかを店舗詳細で確認してください。",
    "smoking-room" => "喫煙所の利用と客席での喫煙は別の条件です。利用できる場所・時間を店舗詳細で確認してください。",
    "heated-only" => "加熱式のみ対応として登録された店舗です。紙たばこを吸える条件ではありません。対象の席・時間も確認してください。"
  }.freeze

  def initialize(directory:, facets:, entry:, facet: nil)
    @directory, @facets, @entry, @facet = directory, facets, entry, facet
  end

  def context
    @entry.fetch("kind") == "station" ? "#{@entry.fetch('label')}周辺" : @entry.fetch("label")
  end

  def overview
    count = data.fetch("count")
    if @facet
      parent = @directory.stats(@entry).fetch("count")
      "#{context}の掲載#{parent}件のうち、#{@facet.fetch('label')}の条件に該当する店舗は#{count}件です。" +
        (@facet.fetch("kind") == "genre" ? "複数ジャンルに登録されている店舗も含みます。" : CONDITIONS.fetch(@facet.fetch("slug")))
    elsif @entry.fetch("kind") == "station"
      "#{@entry.fetch('label')}が登録された最寄駅の店舗を#{count}件掲載しています。徒歩時間や駅の出口は店舗ごとに異なるため、地図・アクセス情報を見比べてください。"
    else
      "#{context}の住所で登録された店舗を#{count}件掲載しています。市区内の駅から探す場合と、喫煙条件から探す場合を使い分けられます。"
    end
  end

  def conditions
    @conditions ||= GeographicFacets::SMOKING.map do |slug, config|
      facet = @facets.definition("smoking", slug)
      source = @facets.stats(@entry, facet)
      count = (data.fetch("ids") & source.fetch("ids")).length
      published = @facets.decision(@entry, facet).fetch(:published)
      { slug: slug, label: config.fetch("label"), count: count, explanation: CONDITIONS.fetch(slug),
        path: published && facet != @facet ? @facets.path(@entry, facet) : nil,
        destination_count: source.fetch("count") }
    end
  end

  def genre_links
    @genre_links ||= @facets.published(@entry).filter_map do |facet|
      next unless facet.fetch("kind") == "genre" && facet != @facet
      source = @facets.stats(@entry, facet)
      count = (data.fetch("ids") & source.fetch("ids")).length
      next if count.zero?
      { label: facet.fetch("label"), count: count, path: @facets.path(@entry, facet), destination_count: source.fetch("count") }
    end.sort_by { |link| [-link[:count], link[:path]] }.first(4)
  end

  def other_stations
    return [] unless @entry.fetch("kind") == "station"
    @other_stations ||= @directory.published("station").filter_map do |entry|
      next if entry.fetch("slug") == @entry.fetch("slug") || !same_registered_region?(entry)
      facet = @facet && @facets.decision(entry, @facet).fetch(:published) ? @facet : nil
      count = (facet ? @facets.stats(entry, facet) : @directory.stats(entry)).fetch("count")
      { label: "#{entry.fetch('label')}#{facet ? 'の' + facet.fetch('label') : 'の店舗一覧'}", count: count,
        path: facet ? @facets.path(entry, facet) : @directory.path(entry) }
    end.sort_by { |link| [-link[:count], link[:path]] }.first(6)
  end

  private

  def same_registered_region?(entry)
    (entry.fetch("regions") & @entry.fetch("regions")).any? do |key|
      ids = @directory.stats(@directory.definition("region", key)).fetch("ids")
      (ids & @directory.stats(@entry).fetch("ids")).any? && (ids & @directory.stats(entry).fetch("ids")).any?
    end
  end

  def data
    @data ||= @facet ? @facets.stats(@entry, @facet) : @directory.stats(@entry)
  end
end
