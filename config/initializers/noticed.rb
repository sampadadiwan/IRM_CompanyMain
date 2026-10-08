# config/initializers/noticed.rb
module EventExtensions
  extend ActiveSupport::Concern

  included do
    belongs_to :entity, optional: true
  end
end

module NotificationExtensions
  extend ActiveSupport::Concern

  def email_delay
    entity = event.entity
    # Randomize the delay so we dont flood aws SES
    delay_seconds = entity.entity_setting.email_delay_seconds
    delay_seconds = delay_seconds.positive? ? rand(1..delay_seconds) : rand(1..300)
    Rails.env.development? ? 0 : delay_seconds
  end

  def investor_access
    if model.respond_to?(:investor) && model.investor.present?
      model.investor.investor_accesses.where(user_id: recipient.id).first
    else
      model.entity.investor_accesses.where(user_id: recipient.id).first
    end
  end

  def email_enabled
    # Either the recipient belongs to the model entity, the investor_access email_enabled is true,
    # or the recipient is an investor advisor authorized by the model's own show? policy - this
    # last check does not require the recipient to currently be switched into the model's entity,
    # since an investor advisor's access does not depend on which persona they're switched into.
    model.entity_id == recipient.entity_id ||
      investor_access&.email_enabled ||
      investor_advisor_show_enabled
  end

  # Deferring to Pundit.policy(...).show? generically (rather than a KYC-specific check) means this
  # is correct for any model/policy that has been made switch-state-independent, not just InvestorKyc
  # - today that's only InvestorKycPolicy#show?, but nothing here assumes that stays true.
  #
  # Gated on an entity-scoped InvestorAdvisor grant (not a bare has_cached_role? check): some
  # policies' #show? is true for reasons unrelated to any advisor grant - e.g. DocumentPolicy#show?
  # returns true unconditionally for a public document - and a cheap role-only gate would dispatch
  # into those too, overriding an explicit investor_access opt-out and emailing every
  # investor-advisor-role recipient app-wide. Scoping to "does this recipient hold a grant on this
  # model's own entity" keeps the dispatch confined to the relationship it exists to recognize.
  #
  # Fails closed (no email) either way, since email_enabled runs outside a controller's rescue_from
  # and a raise here would fail this recipient's delivery job. The two cases differ in whether
  # anyone needs to hear about it:
  #   * Pundit::NotDefinedError - the model has no policy. An expected "no", logged only.
  #   * anything else - a policy's #show? raised. That is a bug the policy owner must see, so it is
  #     reported through ExceptionNotifier rather than only logged: rescuing it quietly would make
  #     it indistinguishable from an intentional denial, and the advisor would just stop getting
  #     emails with nobody the wiser.
  def investor_advisor_show_enabled
    return false unless model.respond_to?(:entity) && model.entity.present?
    return false unless model.entity.investor_advisors.exists?(user_id: recipient.id)

    Pundit.policy!(recipient, model).show?
  rescue Pundit::NotDefinedError => e
    Rails.logger.info { "investor_advisor_show_enabled: no policy for #{model.class.name}##{model.id}, recipient #{recipient.id}: #{e.message}" }
    false
  rescue StandardError => e
    ExceptionNotifier.notify_exception(e, data: investor_advisor_show_failure_report(e))
    false
  end

  # The data block of the ExceptionNotifier email for a failed advisor check: enough to troubleshoot
  # from the email alone - which email, about what, to whom, where they were switched in, what their
  # grant says, which policy raised, and a console line that re-raises it.
  # Worked example X1: openspec/changes/kyc-advisor-notification-delivery-fix/design.md#worked-examples
  def investor_advisor_show_failure_report(error)
    sections = {
      # First, so the email preview says what happened without scrolling.
      summary: -> { "Email to investor advisor skipped: #{Pundit::PolicyFinder.new(model).policy}#show? raised #{error.class} for #{model.class.name}##{model.id}" },
      impact: -> { "Only this recipient's email was skipped; other recipients of this notification were unaffected." },
      reproduce: -> { "Pundit.policy!(User.find(#{recipient.id}), #{model.class.name}.find(#{model.id})).show?" },
      notification: lambda {
        { notifier: event&.type, email_method: event&.params&.dig(:email_method), event_id: event&.id, notification_id: id }
      },
      record: -> { { model: "#{model.class.name}##{model.id}", entity: "#{model.entity&.name} (##{model.entity_id})" } },
      # Where the recipient is switched in right now is the usual cause: most policies assume the
      # user is inside the record's entity, and a switched-out advisor is not.
      recipient: lambda {
        {
          id: recipient.id, email: recipient.email, name: recipient.full_name,
          switched_into: "#{recipient.entity&.name} (##{recipient.entity_id})",
          home_firm: "#{Entity.find_by(id: recipient.advisor_entity_id)&.name} (##{recipient.advisor_entity_id})",
          curr_role: recipient.curr_role, roles: recipient.roles.pluck(:name)
        }
      },
      # The settings the access check reads for a switched-out advisor (InvestorKycPolicy path 2).
      advisor_grant: lambda {
        grant = model.entity.investor_advisors.find_by(user_id: recipient.id)
        next "none" unless grant

        { id: grant.id, allowed_roles: Array(grant.allowed_roles).map(&:to_s),
          enable_kycs: grant.permissions.enable_kycs?, extended_permissions: grant.extended_permissions.to_a }
      },
      policy: -> { Pundit::PolicyFinder.new(model).policy&.name }
    }

    # Each section is gathered on its own, so one failing lookup loses only that section - building
    # the report must never be the thing that breaks delivery or hides the original error.
    sections.transform_values do |build|
      build.call
    rescue StandardError => e
      "could not be gathered: #{e.class}: #{e.message}"
    end
  end

  def whatsapp_enabled
    model.entity.permissions.enable_whatsapp? && # Is WA enabled for the entity
      (
        model.entity_id == recipient.entity_id ||
        (investor_access&.whatsapp_enabled && # Is WA enabled for the investor access specified by the entity
        recipient.whatsapp_enabled && # Is WA enabled for the recipient
        recipient.phone.present?) # Does the recipient have a phone number
      )
  end

  # Gates the :email deliver_by itself (see BaseNotifier) so a blank-body custom notification
  # never even enqueues the mailer job - there's nothing worth sending, and no default body to
  # fall back to. True for every notifier that has no CustomNotification concept at all (most
  # don't define `custom_notification` via `notification_methods`), or when no CustomNotification
  # is configured (nil) - only an actually-resolved-but-blank body is skipped. A Trix rich-text
  # body can save as "<div><br></div>" and still be a non-empty string, so a plain #blank? check
  # on the raw HTML isn't enough.
  def custom_notification_body_present?
    return true unless respond_to?(:custom_notification)

    cn = custom_notification
    return true if cn.nil?

    ActionView::Base.full_sanitizer.sanitize(cn.body.to_s).present?
  end

  # Gates the :whats_app deliver_by itself (see BaseNotifier) so it never even enqueues the
  # delivery job unless there's an actual message to send. Unlike custom_notification_body_present?,
  # this defaults to false (skip) when there's no CustomNotification concept at all or none is
  # configured - WhatsApp has no hardcoded default message anywhere (every mailer has one; nothing
  # sends WhatsApp content except CustomNotification#whatsapp), so "no CustomNotification" and "blank
  # whatsapp field" both mean "nothing to send" here, not just the blank-field case.
  def custom_notification_whatsapp_present?
    return false unless respond_to?(:custom_notification)

    cn = custom_notification
    return false if cn.nil?

    ActionView::Base.full_sanitizer.sanitize(cn.whatsapp.to_s).present?
  end

  def model
    # The new way is to store the record in the event
    # The old way was to store the record in params

    # The actual model is stored in params
    # The key is model name in lowercase
    # To get the model name, we use the notifier name and remove the Notifier part
    event.record.presence || params[:"#{self.class.name.split('::').first.gsub('Notifier', '').gsub('Download', '').underscore}"]
  end

  def entity_id
    # Prefer the persisted column (set by ApplicationMailer#mark_delivered during delivery).
    # Falls back to deriving from event.record for notifications that predate bounce-tracking
    # columns, and for callers that don't go through mark_delivered.
    read_attribute(:entity_id).presence || (model&.entity_id if model.respond_to?(:entity_id))
  end
end

Rails.application.config.to_prepare do
  # You can extend Noticed::Event or Noticed::Notification here
  Noticed::Event.include EventExtensions
  Noticed::Notification.include NotificationExtensions

  # Ransack allowlists — must be in to_prepare so they survive dev reloads
  Noticed::Event.class_eval do
    def self.ransackable_attributes(_auth_object = nil)
      %w[created_at type record_type record_id].sort
    end

    def self.ransackable_associations(_auth_object = nil)
      []
    end
  end

  Noticed::Notification.class_eval do
    def self.ransackable_attributes(_auth_object = nil)
      %w[created_at user_email email_sent read_at whatsapp whatsapp_sent subject skip_reason skip_reported_at].sort
    end

    def self.ransackable_associations(_auth_object = nil)
      [:event]
    end

    ransacker :user_email, formatter: proc { |v| v.downcase } do |_parent|
      Arel.sql(<<~SQL.squish)
        CASE
          WHEN noticed_notifications.recipient_type = 'User' THEN (
            SELECT LOWER(users.email)
            FROM users
            WHERE users.id = noticed_notifications.recipient_id
          )
        END
      SQL
    end
  end
end
