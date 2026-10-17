class BaseNotifier < Noticed::Event
  # belongs_to :entity

  if Rails.env.test?
    deliver_by :whats_app, class: "DeliveryMethods::WhatsApp" do |config|
      # Hard safety kill-switch, unrelated to the content check below - unlike email (captured
      # safely by Rails' :test delivery adapter), a WhatsApp send is a raw Net::HTTP call to the
      # real WATI API, so this must stay forced off regardless of whether a message is present.
      config.if = -> { false }
    end
    # deliver_by :email, mailer: :mailer_name, method: :email_method, format: :email_data
    deliver_by :email do |config|
      config.if = lambda {
        custom_notification_body_present? # Still gate on this in test, so blank-body scenarios can be exercised
      }
      config.mailer = :mailer_name
      config.method = :email_method
      config.params = :email_data
    end
  else
    # investor_access is a method defined in NotificationExtensions
    # email_delay is a method defined in NotificationExtensions
    deliver_by :whats_app, class: "DeliveryMethods::WhatsApp" do |config|
      config.if = lambda {
        # Is WA enabled for this recipient/entity, and is there actually a message to send
        # (see NotificationExtensions#custom_notification_whatsapp_present?)
        whatsapp_enabled && custom_notification_whatsapp_present?
      }
      config.wait = :email_delay
    end

    deliver_by :email do |config|
      config.if = lambda {
        # Is email enabled for the investor access specified by the entity, and does this
        # notification actually have content to send (see NotificationExtensions)
        email_enabled && custom_notification_body_present?
      }
      config.mailer = :mailer_name # Setup by each notifier
      config.method = :email_method # Typically the method name sent via the params :email_method
      config.params = :email_data # Setup by each notifier
      config.wait = :email_delay # This is defined in NotificationExtensions in initializers/noticed.rb
    end
  end

  # LP mobile app push (lp-mobile-app design card ⑤), in every environment — features stub Expo
  # with WebMock. Gated by NotificationExtensions#push_enabled: the email gate plus push-only checks.
  # Not delayed: email_delay exists to spread SES load, which push does not share (decision 7).
  deliver_by :push, class: "DeliveryMethods::ExpoPush" do |config|
    # Checked BEFORE a job is queued: Noticed evaluates `if` inside the delivery job, so without
    # this every notification would queue a push job even in a region without push or for the
    # many recipients with no phone. Cheap checks only (two config reads, one SELECT 1).
    config.before_enqueue = -> { throw(:abort) unless push_candidate? }
    # The full gate (email rules, category) runs in the job
    config.if = -> { push_enabled }
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

  # This method is used to find the investor_advisor_id for the recipient of the email
  # If the recipient is an investor_advisor, it will return the advisor's ID
  # Otherwise, it will return nil
  # @see WithAuthentication.switch_advisor
  def investor_advisor_id(investor_entity_id, user_id)
    return params[:investor_advisor_id] if params[:investor_advisor_id].present?

    user = User.find(user_id)
    if user.has_cached_role?(:investor_advisor)
      @investor_advisor ||= InvestorAdvisor.where(entity_id: investor_entity_id, user_id:).last
      @investor_advisor&.id
    end
  end
end
