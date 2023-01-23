class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SUPPORT_EMAIL", nil)
  layout "mailer"

  def sandbox_email(model, emails)
    model.entity.entity_setting.sandbox ? model.entity.entity_setting.sandbox_emails : emails
  end

  def from_email(entity)
    @current_entity = entity
    @current_entity.entity_setting.from_email.presence || ENV.fetch("SUPPORT_EMAIL", nil)
  end
end
