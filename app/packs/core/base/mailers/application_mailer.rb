class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SUPPORT_EMAIL", nil)
  layout "mailer"

  # This will cause the to from and cc to be set from the entity and user
  # Note it will ensure that
  before_action :setup_defaults
  def setup_defaults
    @entity = Entity.find(params[:entity_id]) if params[:entity_id]
    @user = User.find(params[:user_id]) if params[:user_id]

    if @entity.present?
      # Ensure we pick te right from address
      @from = from_email(@entity)

      @cc = @entity.entity_setting.cc
      # Sometimes we have an ovveride for the cc field in the investor access
      investor_cc = @entity.investor_accesses.where(email: @user.email).first&.cc
      if (@cc.nil? || @cc.blank?) && investor_cc.present?        
        @cc = investor_cc
      elsif @cc.present? && investor_cc.present?
        @cc += ",#{investor_cc}"
      end

      @reply_to = @entity.entity_setting.reply_to.presence || @cc.presence || @from
    end

    if @user.present?
      # Ensure we send to sanbox if required
      @to = @entity.entity_setting.sandbox ? @entity.entity_setting.sandbox_emails : @user.email
    end
  end

  def sandbox_email(model, emails)
    model.entity.entity_setting.sandbox ? model.entity.entity_setting.sandbox_emails : emails
  end

  def sandbox_whatsapp_numbers(model, numbers)
    model.entity.entity_setting.sandbox ? model.entity.entity_setting.sandbox_numbers.to_s.split(',') : numbers
  end

  def from_email(entity)
    @current_entity = entity
    @current_entity.entity_setting.from_email.presence || ENV.fetch("SUPPORT_EMAIL", nil)
  end

  # Convinience method to send mail with simply the subject
  def send_mail(subject: nil)
    mail(from: @from, to: @to, cc: @cc, reply_to: @reply_to, subject:)
  end
end
