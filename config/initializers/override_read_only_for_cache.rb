# https://github.com/rails/solid_cache/issues/238
module OverrideReadOnlyForCache
  def readonly?
    false
  end
end

Rails.application.config.after_initialize do
  SolidCache::Entry.prepend(OverrideReadOnlyForCache)
end
