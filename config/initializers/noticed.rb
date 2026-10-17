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

  # The folio (Investor) this notification is about, or nil when none can be found. A person can
  # hold one InvestorAccess per folio in the same fund, each with its own email/WhatsApp switches,
  # so the channel gates must read the access of THIS folio - never "the recipient's first access
  # in the fund", which silently applied another folio's switches.
  # Report: openspec/changes/fix-notification-investor-access-resolution/report.md
  def notification_investor
    # H1 / X1 - the sender names the folio it fanned out for (DocumentSender passes investor_id).
    # Scoped to the record's fund so a stray id can never pull in another fund's investor.
    # X2 - an id that no longer resolves falls through to the record instead of raising.
    if params[:investor_id].present?
      investor = Investor.find_by(id: params[:investor_id], entity_id: model.entity_id)
      return investor if investor
    end

    # H2 - records that name their own investor (commitments, remittances, KYCs, ...)
    return model.investor if model.respond_to?(:investor) && model.investor.present?

    # E1 / E4 - a Document names no investor itself, but its owner usually does: a commitment
    # (statements, CAS, Form 16A), a remittance, a KYC... or the owner IS the Investor.
    return unless model.respond_to?(:owner)

    owner = model.owner
    return owner if owner.is_a?(Investor)

    owner.investor if owner.respond_to?(:investor)
  end

  # The recipient's access on this notification's folio; nil when the folio is unknown (E2) or the
  # recipient has no access on it (X1). Deliberately no fallback to another folio's access.
  def investor_access
    notification_investor&.investor_accesses&.find_by(user_id: recipient.id)
  end

  # Whether the given channel switch (:email_enabled / :whatsapp_enabled) is on for this recipient.
  # Folio known -> that folio's access decides (H1, H3, E3, X1).
  # Folio unknown (fund-level document, User/Task/... records) -> on if ANY of the recipient's
  # accesses in this fund has it on (E2): they are a chosen recipient and have opted in to this
  # fund on at least one folio. exists?, not a load - see CLAUDE.md large-table hygiene.
  def folio_channel_enabled?(switch)
    if notification_investor
      investor_access&.public_send(switch)
    else
      model.entity.investor_accesses.where(user_id: recipient.id).exists?(switch => true)
    end
  end

  def email_enabled
    # Either the recipient belongs to the model entity, the folio's investor_access email_enabled is
    # true, or the recipient is an investor advisor authorized by the model's own show? policy - this
    # last check does not require the recipient to currently be switched into the model's entity,
    # since an investor advisor's access does not depend on which persona they're switched into.
    enabled = model.entity_id == recipient.entity_id ||
              folio_channel_enabled?(:email_enabled) ||
              (!named_contact_on_folio? && investor_advisor_show_enabled)

    # X3 - the skip happens in deliver_by's config.if, before any mailer runs, so no skip_reason is
    # ever written. Log which folio and access decided it, so "Email sent: No" can be traced.
    unless enabled
      Rails.logger.info do
        "email_enabled false: notification #{id}, recipient #{recipient.id}, " \
          "investor #{notification_investor&.id.inspect}, access #{investor_access&.id.inspect}"
      end
    end

    enabled
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
  # The recipient is a named contact on this notification's folio, so that contact row's own
  # email switch (folio_channel_enabled?) is the answer and the advisor-grant override below must
  # not reverse an explicit opt-out. Without this, a Fund Advisor of the fund manager who opted out
  # on their OWN investor's row was emailed anyway once their own records became visible to them
  # at home. Worked example E13 — openspec/changes/fix-advisor-own-investor-access/report.md#verification
  def named_contact_on_folio?
    notification_investor.present? && investor_access.present?
  end

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
        (folio_channel_enabled?(:whatsapp_enabled) && # Is WA enabled on this folio's investor access (E3)
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
  # Gates the :push deliver_by (see BaseNotifier) — LP mobile app push, design card ⑤/⑥.
  # Push goes only where the email would go, plus three push-only checks, cheapest first:
  #   X20  push is configured for this region (an Expo access token exists)
  #   E11  the recipient is not a member of the entity that sent it — internal alerts are never pushed
  #   E10  the recipient has this notification's category switched on
  #        the recipient has a live, push-enabled phone (SELECT 1 … LIMIT 1 — most LPs have none)
  #   E9 / E13  the email for this notification would be sent (email_enabled + a body to send)
  # Worth queuing a push job at all? Push configured in this region and the recipient has a live,
  # push-enabled phone. Runs before enqueue (BaseNotifier), so it must stay cheap.
  def push_candidate?
    ExpoPushClient.configured? && recipient.respond_to?(:mobile_devices) && recipient.mobile_devices.pushable.exists?
  rescue StandardError
    false
  end

  def push_enabled
    ExpoPushClient.configured? &&
      model.entity_id != recipient.entity_id &&
      MobilePushCategory.enabled_for?(recipient, event) &&
      recipient.mobile_devices.pushable.exists? &&
      email_enabled &&
      custom_notification_body_present?
  rescue StandardError => e
    # A gate that raises would fail the whole delivery job; push is best-effort, so log and skip
    Rails.logger.warn("[push_enabled] notification #{id}: #{e.class}: #{e.message}")
    false
  end

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
