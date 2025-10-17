# app/helpers/locale_helper.rb
module LocaleHelper
  # uses current (user) locale – normal behavior
  def user_t(key, **)
    I18n.t(key, **)
  end

  # force system locale for certain labels
  def sys_t(key, **)
    I18n.t(key, **, locale: ENV.fetch("APP_LOCALE", "en").to_sym)
  end

  # localized formatting with system locale
  def sys_l(obj, **)
    I18n.l(obj, **, locale: ENV.fetch("APP_LOCALE", "en").to_sym)
  end
end
