class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SUPPORT_EMAIL", nil)
  layout "mailer"

  def sandbox_email(model, emails)
    model.entity.sandbox ? model.entity.sandbox_emails : emails
  end

  def from_email(entity)
    @current_entity = entity
    @current_entity.from_email.presence || ENV.fetch("SUPPORT_EMAIL", nil)
  end
end
