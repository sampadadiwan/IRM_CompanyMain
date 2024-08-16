class BaseNotifier < Noticed::Event
  if Rails.env.test?
    deliver_by :whats_app, class: "DeliveryMethods::WhatsApp" do |config|
      config.if = -> { false }
    end
    # deliver_by :email, mailer: :mailer_name, method: :email_method, format: :email_data
    deliver_by :email do |config|
      config.mailer = :mailer_name
      config.method = :email_method
      config.params = :email_data
    end
  else
    # investor_access is a method defined in NotificationExtensions
    # email_delay is a method defined in NotificationExtensions
    deliver_by :whats_app, class: "DeliveryMethods::WhatsApp" do |config|
      config.if = lambda {
        event.entity.permissions.enable_whatsapp? && # Is WA enabled for the entity
          investor_access.whatsapp_enabled && # Is WA enabled for the investor access specified by the entity
          recipient.whatsapp_enabled && # Is WA enabled for the recipient
          recipient.phone.present? # Does the recipient have a phone number
      }
      config.wait = :email_delay
    end

    deliver_by :email do |config|
      config.if = lambda {
        investor_access.email_enabled # Is email enabled for the investor access specified by the entity
      }
      config.mailer = :mailer_name # Setup by each notifier
      config.method = :email_method # Typically the method name sent via the params :email_method
      config.params = :email_data # Setup by each notifier
      config.wait = :email_delay # This is defined in NotificationExtensions in initializers/noticed.rb
    end
  end

  required_param :entity_id

  def mailer_name(notification = nil)
    raise NotImplementedError
  end

  def email_method(_notification = nil)
    params[:email_method]
  end

  def entity
    @entity ||= Entity.find(params[:entity_id])
  end
end
