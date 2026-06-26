module WithLocale
  extend ActiveSupport::Concern

  included do
    before_action :set_locale
  end

  def set_locale
    # Priority: params[:locale] > session[:locale] > browser
    # I18n.locale = params[:locale]&.to_sym || session[:locale]&.to_sym || extract_locale_from_accept_language_header || I18n.default_locale
    I18n.locale = extract_locale_from_accept_language_header || I18n.default_locale
    Rails.logger.debug { "Locale set to: #{I18n.locale}" }
    # session[:locale] = I18n.locale
  end

  def extract_locale_from_accept_language_header
    # Looks at browser settings: Accept-Language
    http_accept_language = request.env['HTTP_ACCEPT_LANGUAGE']
    Rails.logger.debug { "Accept-Language header: #{http_accept_language.inspect}" }
    return nil if http_accept_language.blank?

    # First try full locale codes (e.g. "en-US", "ja-JP") to prefer specific over generic
    full_locales = http_accept_language.scan(/([a-z]{2}(?:-[A-Z]{2})?)/).flatten
    Rails.logger.debug { "Parsed locales from header: #{full_locales.inspect}" }
    result = full_locales.find { |locale| I18n.available_locales.include?(locale.to_sym) }
    Rails.logger.debug { "Matched locale: #{result.inspect}" }
    result
  end
end
