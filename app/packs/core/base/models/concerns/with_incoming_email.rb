module WithIncomingEmail
  extend ActiveSupport::Concern

  included do
    has_many :incoming_emails, as: :owner, dependent: :destroy
  end

  # convert class_name and id to email address
  # This is used to send emails to the this object
  # See IncomingEmail.set_owner
  def incoming_email_address
    "#{self.class.name.underscore}.#{id}@#{ENV.fetch('INCOMING_EMAIL_DOMAIN', nil)}"
  end
end
