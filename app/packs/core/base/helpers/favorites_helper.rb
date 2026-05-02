# app/packs/core/base/helpers/favorites_helper.rb
module FavoritesHelper
  def favorite_url_for(record = nil, url: nil)
    return url if url.present?
    return polymorphic_path(record) if record.present?

    request.fullpath
  end

  def favorite_title_for(record = nil, title: nil)
    return title if title.present?

    return record.name if record.respond_to?(:name)
    return record.title if record.respond_to?(:title)

    record.present? ? record.class.model_name.human : controller_name.humanize
  end

  def favorite_title
    return @favorite_title if defined?(@favorite_title) && @favorite_title.present?

    return @bread_crumbs.to_a.last.first if defined?(@bread_crumbs) && @bread_crumbs.present?

    controller_name.humanize
  end

  def favorite_url
    return @favorite_url if defined?(@favorite_url) && @favorite_url.present?

    request.fullpath
  end
end
