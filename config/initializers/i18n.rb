# config/initializers/z99_i18n.rb  (z99 to run late)
require "i18n/backend/fallbacks"

I18n::Backend::Simple.include I18n::Backend::Fallbacks

I18n.available_locales = %i[en en-US ja]
I18n.default_locale    = ENV.fetch("APP_LOCALE", "en").to_sym
I18n.fallbacks.map('en-US': %i[en-US en], ja: %i[ja en], en: [:en])
