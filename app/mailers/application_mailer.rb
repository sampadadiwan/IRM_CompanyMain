class ApplicationMailer < ActionMailer::Base
  default from: ENV["SUPPORT_EMAIL"]
  layout "mailer"

  def sandbox_email(model, emails)
    model.entity.sandbox ? model.entity.sandbox_emails : emails
  end
end
