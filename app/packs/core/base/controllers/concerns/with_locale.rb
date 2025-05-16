module WithLocale
  extend ActiveSupport::Concern

  included do
    before_action :set_locale
  end

  def set_locale
    # Priority: params[:locale] > session[:locale] > browser
    I18n.locale = params[:locale]&.to_sym || session[:locale]&.to_sym || extract_locale_from_accept_language_header || I18n.default_locale
    Rails.logger.debug { "Locale set to: #{I18n.locale}" }
    session[:locale] = I18n.locale
  end

  def extract_locale_from_accept_language_header
    # Looks at browser settings: Accept-Language
    http_accept_language = request.env['HTTP_ACCEPT_LANGUAGE']
    return nil if http_accept_language.blank?

    # Find the first available locale that matches
    parsed_locales = http_accept_language.scan(/[a-z]{2}/)
    parsed_locales.find { |locale| I18n.available_locales.include?(locale.to_sym) }
  end

  def with_owner_access(relation, raise_error: true)
    if params[:owner_id].present? && params[:owner_type].present?
      unless current_user.company_admin?
        # If owner is passed, check if user is authorized to view the owner
        @owner = params[:owner_type].constantize.find(params[:owner_id])
        authorize(@owner, :show?)
      end
      relation.where(owner_id: params[:owner_id], owner_type: params[:owner_type])
    elsif !current_user.company_admin? && raise_error
      # Raise AccessDenied if user is an employee and no owner is passed
      raise Pundit::NotAuthorizedError
    else
      relation
    end
  end

  def get_q_param(name)
    value = nil
    @q.conditions.each do |condition|
      #   # Check if the condition's attribute (name) is 'interest_id'
      value = condition.values.map(&:value).first if condition.attributes.map(&:name).include?(name.to_s)
    end
    value
  end
end
