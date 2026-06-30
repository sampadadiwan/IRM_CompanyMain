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

    # Parse locales in header priority order (e.g. "en-IN,en-US;q=0.9,en;q=0.8" → ["en-IN","en-US","en"])
    full_locales = http_accept_language.scan(/([a-z]{2}(?:-[A-Z]{2})?)/).flatten
    Rails.logger.debug { "Parsed locales from header: #{full_locales.inspect}" }

    full_locales.each do |locale|
      # Exact match wins
      if I18n.available_locales.include?(locale.to_sym)
        Rails.logger.debug { "Matched locale: #{locale.inspect}" }
        return locale
      end

      # Before moving to other specific variants (e.g. en-US), try the base language first
      # so en-IN → en (dd/mm/yyyy) rather than falling through to en-US (mm/dd/yyyy)
      base = locale.split('-').first
      if I18n.available_locales.include?(base.to_sym)
        Rails.logger.debug { "Matched base locale: #{base.inspect} (from #{locale.inspect})" }
        return base
      end
    end

    nil
  end
end
