class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SUPPORT_EMAIL_FROM", nil)
  layout "mailer"

  # Every l(date)/l(time) call in a mailer view renders dd-Mon-YYYY, regardless of the
  # site's own date.formats.default — see EmailDateLocalization.
  helper EmailDateLocalization

  # Templates render through an ActionView context, not the mailer instance itself,
  # so a plain instance method (adhoc_notification_link, defined below) isn't visible
  # to the view unless explicitly exposed like this.
  helper_method :adhoc_notification_link

  # Safe, non-ERB placeholders clients can type into a CustomNotification body, e.g. {{user_full_name}}.
  # Resolved against the mailer instance's own ivars in CustomNotification#render_safe_body - never eval'd.
  # Subclasses add their own via PLACEHOLDERS = superclass::PLACEHOLDERS.merge(...).freeze
  PLACEHOLDERS = {
    "user_full_name" => ->(m) { m.instance_variable_get(:@user)&.full_name },
    "user_first_name" => ->(m) { m.instance_variable_get(:@user)&.first_name },
    "user_last_name" => ->(m) { m.instance_variable_get(:@user)&.last_name },
    "user_email" => ->(m) { m.instance_variable_get(:@user)&.email },
    "entity_name" => ->(m) { m.instance_variable_get(:@entity)&.name }
  }.freeze

  after_deliver :mark_delivered
  def mark_delivered
    # after_deliver callbacks run unconditionally — ActionMailer::MessageDelivery#deliver_now/
    # deliver_now! always wrap delivery in run_callbacks(:deliver), even when the mailer action
    # never called mail(...) (e.g. record_notification_skip returns early without sending). In
    # that case @_message is a NullMail and @_mail_was_called is false; the bare `mail` call below
    # would then re-invoke the `mail(headers = {})` DSL method for the first time with no headers,
    # which tries to render a template using the default mailer/action path (e.g.
    # "capital_commitment_mailer/adhoc_notification" instead of the actual
    # "application_mailer/adhoc_notification" template) and raises ActionView::MissingTemplate.
    # There's nothing to record for a message that was never built, so bail out first.
    return unless @_mail_was_called

    begin
      # Lets update the notification to say we have sent the email with details
      # This is because if we have attachments, then we only want to body which is in mail.parts[0]

      db_mail_body = mail&.parts.present? ? mail.parts[0] : mail
    rescue StandardError
      db_mail_body = mail
    end

    # Save the email sent, subject and email details, plus bounce-tracking correlation
    # (tracking_id/entity_id are only ever set when @notification is present — see
    # tag_for_bounce_tracking; bounce tracking is notifier-driven sends only, by design).
    # rubocop:disable Rails/SkipsModelValidations
    begin
      @notification&.update_columns(
        email: { email: { to: @to, from: @from, cc: @cc, reply_to: @reply_to, params:, mail: db_mail_body } },
        email_sent: true,
        subject: message.subject.truncate(254),
        entity_id: @entity&.id
      )
      # Set tracking_id only on first delivery — never overwrite an existing value.
      # A re-send generates a fresh UUID but the first delivery's X-CapHive-Tracking-Id
      # header is already in flight with SES; overwriting would orphan that correlation.
      # The @email_tracking_id.present? guard also prevents a nil write if
      # tag_for_bounce_tracking was skipped for any reason.
      if @notification && @email_tracking_id.present?
        Noticed::Notification.where(id: @notification.id, tracking_id: nil)
                             .update_all(tracking_id: @email_tracking_id)
      end
    rescue StandardError => e
      Rails.logger.error("mark_delivered DB write failed for notification #{@notification&.id}: #{e.message}")
    end
    # rubocop:enable Rails/SkipsModelValidations
  end

  # This will cause the to from and cc to be set from the entity and user
  # Note it will ensure that
  before_action :setup_defaults
  before_action :tag_for_bounce_tracking
  def setup_defaults
    # Set the notification if this email was triggered by a notification, used in mark_delivered()
    @notification = Noticed::Notification.find(params[:notification_id]) if params[:notification_id]

    # Set the entity and user
    @entity = Entity.find(params[:entity_id]) if params[:entity_id]
    @user = User.find(params[:user_id]) if params[:user_id]
    @additional_ccs ||= params[:additional_ccs]

    if @entity.present?
      # Ensure we pick te right from address, sometimes funds like to send from an email specified in from_email. See Notifiers in funds
      @from = params[:from_email].presence || from_email(@entity)

      unless @entity.entity_setting.sandbox
        setup_cc
        @reply_to = @entity.entity_setting.reply_to.presence || @cc.presence || @from
      end

      if @notification && @notification.model.is_a?(WithIncomingEmail)
        # This model can receive inbound emails
        @reply_to = if @reply_to.present?
                      "#{@reply_to},#{@notification.model.incoming_email_address}"
                    else
                      "#{@from},#{@notification.model.incoming_email_address}"
                    end
      end

    end

    if @user.present?
      # Ensure we send to sanbox if required
      @to = @entity.entity_setting.sandbox ? @entity.entity_setting.sandbox_emails : @user.email
    end
  end

  # Tags outgoing messages that are tied to a Noticed::Notification so SES bounce/complaint
  # notifications can be correlated back to that specific notification — see mark_delivered.
  # Deliberately scoped to notifier-driven sends only: mailers invoked directly without a
  # notification (magic links, KYC reminders, AI digest mailers, etc.) are left untagged, so
  # SES never publishes bounce/complaint events for them and they don't appear in the report.
  # X-CapHive-Tracking-Id is echoed back by SES inside the SNS payload's mail.headers;
  # X-SES-CONFIGURATION-SET tells SES which config set (and therefore which SNS topic) to
  # publish Bounce/Complaint events to. The latter is only set when SES_CONFIGURATION_SET is
  # configured (e.g. unset in dev/test), so plain SMTP sends there are unaffected.
  def tag_for_bounce_tracking
    return unless @notification

    @email_tracking_id = SecureRandom.uuid
    headers["X-CapHive-Tracking-Id"] = @email_tracking_id
    headers["X-SES-CONFIGURATION-SET"] = ENV["SES_CONFIGURATION_SET"] if ENV["SES_CONFIGURATION_SET"].present?
  end

  def setup_cc
    @cc = @entity.entity_setting.cc
    # Sometimes we have an override for the cc field in the investor access
    investor_cc = @entity.investor_accesses.where(email: @user.email, investor_id: params[:investor_id]).first&.cc if @user && params[:investor_id].present?
    if @user && (@cc.nil? || @cc.blank?) && investor_cc.present?
      @cc = investor_cc
    elsif @cc.present? && investor_cc.present?
      @cc += ",#{investor_cc}"
    end

    # Sometimes we have an ovveride for the cc field ex commitment specific cc
    if @additional_ccs
      @cc.present? ? @cc += ",#{@additional_ccs}" : @cc = @additional_ccs
    end

    # Never CC the recipient on their own email — avoids duplicate delivery when
    # entity_setting.cc matches a fund employee who is also a direct recipient.
    if @cc.present? && @user.present?
      cc_list = @cc.split(",").map(&:strip).reject { |addr| addr.casecmp?(@user.email) }
      @cc = cc_list.any? ? cc_list.join(", ") : nil
    end
  end

  def sandbox_email(model, emails)
    model.entity.entity_setting.sandbox ? model.entity.entity_setting.sandbox_emails : emails
  end

  def sandbox_whatsapp_numbers(model, numbers)
    model.entity.entity_setting.sandbox ? model.entity.entity_setting.sandbox_numbers.to_s.split(',') : numbers
  end

  def from_email(entity)
    @current_entity ||= entity
    @current_entity.entity_setting.from_email.presence || ENV.fetch("SUPPORT_EMAIL_FROM", nil)
  end

  # attachment_names entries resolve independently along two axes:
  #   pattern:      plain text -> exact match   |  contains '*' -> wildcard/substring match
  #   multiplicity: latest_doc_only=true -> newest match only  |  false -> every match
  #
  # The entry is squished before matching, so a doubled space typed into attachment_names still
  # matches - see documents_matching_attachment_name.
  #
  # Examples (attachment_names entry -> latest_doc_only -> result):
  #   "Statement of Account"    -> true  -> exact match,     newest "Statement of Account" only
  #   "*Statement of Account*"  -> true  -> substring match, newest match only (old fuzzy_match=true behavior)
  #   "SOA_*_03_2026"           -> false -> wildcard match,  every matching document attached
  #   "Statement of Account"    -> false -> exact match,     every doc named exactly "Statement of Account" attached
  def attach_custom_notification_documents
    if @custom_notification && @custom_notification.documents.present?
      @custom_notification.documents.each do |document|
        pw_protect_attach_file(document, @custom_notification)
      end
    end

    if @custom_notification && @custom_notification.attachment_names.present? && custom_notification_documents_owner.respond_to?(:documents)
      latest_doc_only = @custom_notification.latest_doc_only
      attachment_name_list.each do |name|
        documents = documents_matching_attachment_name(name)
        documents = documents.limit(1) if latest_doc_only
        documents.each { |document| pw_protect_attach_file(document, @custom_notification) }
      end
    end
  end

  # @custom_notification.attachment_names, parsed into individual names. CSV.parse_line so a
  # name containing a literal comma (e.g. a date range like "01 July,2025 to 31 December,2025")
  # can be protected by wrapping it in quotes; unquoted entries still split on comma exactly
  # like before. Falls back to a plain comma split if the value has unbalanced quotes, so a
  # typo can't silently drop all attachments.
  def attachment_name_list
    return [] if @custom_notification&.attachment_names.blank?

    names = begin
      CSV.parse_line(@custom_notification.attachment_names).to_a
    rescue CSV::MalformedCSVError
      @custom_notification.attachment_names.split(',')
    end
    names.compact.map(&:strip).compact_blank
  end

  # The documents matching one attachment_names entry on custom_notification_documents_owner —
  # shared by attach_custom_notification_documents and missing_mandatory_attachment_names so
  # both use the exact same wildcard-vs-exact resolution rule.
  #
  # The PATTERN is squished before use; the stored name is not touched. It doesn't need to be:
  # Document normalizes :name with squish, and migration 20260814100000 backfilled every row
  # written before that, so document names in the database carry no stray whitespace. Squishing
  # the pattern is what covers an attachment_names entry typed or pasted with a doubled space.
  #
  # This deliberately leaves the comparison itself in SQL rather than doing it in Ruby.
  # documents.name is utf8mb4_0900_ai_ci: MySQL treats "Konig" and "König" as equal and gives
  # zero weight to formatting characters, so "- Ishan" matches "- <U+2060>Ishan" — and real
  # document names here contain both accents and zero-width joiners. A Ruby comparison
  # (casecmp?/Regexp) is case-insensitive only, so it would silently stop matching those rows.
  # Keeping the match in the database preserves that behavior exactly, and keeps the relation
  # lazy so latest_doc_only's .limit(1) still becomes a SQL LIMIT instead of loading every match.
  #
  # exclude_generated_unapproved drops a generated-but-unapproved document from the match
  # entirely (regardless of attachment_mandatory) - we never send those. That also means an
  # attachment_names entry whose only match is generated-but-unapproved is treated as absent,
  # so it can trigger missing_mandatory_attachment_names just like a genuinely missing document.
  def documents_matching_attachment_name(name)
    pattern = name.to_s.squish
    documents = if pattern.include?('*')
                  custom_notification_documents_owner.documents.where("name like ? ESCAPE ?", wildcard_to_like(pattern), '\\')
                else
                  custom_notification_documents_owner.documents.where(name: pattern)
                end
    documents.exclude_generated_unapproved.order(created_at: :desc)
  end

  # attachment_names entries that resolve to zero documents for the current recipient's owner —
  # always empty unless @custom_notification.attachment_mandatory? is on, since a missing name
  # is otherwise just silently skipped (see attach_custom_notification_documents above).
  def missing_mandatory_attachment_names
    return [] unless @custom_notification&.attachment_mandatory?
    return [] if attachment_name_list.blank? || !custom_notification_documents_owner.respond_to?(:documents)

    attachment_name_list.reject { |name| documents_matching_attachment_name(name).exists? }
  end

  # Marks this recipient's Noticed::Notification as skipped instead of sending it, when
  # attachment_mandatory is on and a required document is missing. Guarded on @notification
  # being present — that's only ever true for real notifier-driven sends (see
  # custom_notification_documents_owner above); previews build no Notification and should keep
  # rendering normally rather than silently going blank. entity_id is set explicitly here
  # because mark_delivered's after_deliver callback (which normally sets it) never fires for a
  # send we're not making.
  #
  # Schedules SkippedNotificationReportJob itself (not cron-scheduled) so the report only ever
  # runs in response to an actual skip, never on a blind timer. The delay gives sibling
  # recipient jobs from the same trigger a chance to finish first, so they're more likely to be
  # swept into one report instead of several.
  def record_notification_skip(missing_names)
    return unless @notification

    @notification.update_columns(
      skip_reason: "Missing required attachment(s): #{missing_names.join(', ')}",
      entity_id: @entity&.id
    )
    schedule_skipped_notification_report(@custom_notification.id)
  rescue StandardError => e
    Rails.logger.error("record_notification_skip failed for notification #{@notification&.id}: #{e.message}")
  end

  # A burst of skips from the same trigger (e.g. 12 commitments missing the same document) would
  # otherwise enqueue SkippedNotificationReportJob 12 times. Rails.cache.write(unless_exist: true)
  # only succeeds for whichever caller gets there first within the window — that caller schedules
  # the one job; every other skip inside the window is a no-op here. Scoped per custom_notification_id
  # (not a single global key) so a burst on one notification template doesn't debounce-block the
  # report for an unrelated one skipped in the same window. (In test, cache_store is :null_store,
  # which never remembers a key, so every call there "claims" — no debounce in tests, which is
  # fine since each scenario only produces one skip.)
  def schedule_skipped_notification_report(custom_notification_id)
    cache_key = "skipped_notification_report:scheduled:#{custom_notification_id}"
    claimed = Rails.cache.write(cache_key, true, unless_exist: true, expires_in: 5.minutes)
    SkippedNotificationReportJob.set(wait: 5.minutes).perform_later(custom_notification_id) if claimed
  end

  # The resource whose `documents` association should be searched when resolving
  # CustomNotification#attachment_names. Defaults to the live Noticed::Notification's
  # model (set only on real, notifier-driven sends). Preview builds no Notification, so
  # subclasses reachable from WithEmailPreview override this to return their own
  # already-resolved resource ivar instead — which is the same object in production too
  # (each notifier passes record: self, and the mailer's before_action derives its ivar
  # from that same record's id).
  #
  # private (scoped to just this method, not a `private` section — adhoc_notification and
  # others below must stay public actions): keeps this internal resolver out of
  # CustomNotification#email_methods, which reads instance_methods(false) on each mailer
  # to populate the "For Notification" dropdown.
  private def custom_notification_documents_owner
    @notification&.model
  end

  def attach_doc(document)
    file = document.file
    # Add the file to the document
    attachments["#{document.name}.#{document.uploaded_file_extension}"] = file.read
    file.close
    # Cleanup
    File.delete(file) if file.instance_of?(::File)
  end

  # Converts a '*' wildcard pattern (e.g. "SOA_*_03_2026") into a SQL LIKE pattern,
  # escaping any literal %/_ characters in the non-wildcard parts.
  def wildcard_to_like(name)
    name.split('*', -1).map { |part| ActiveRecord::Base.sanitize_sql_like(part) }.join('%')
  end

  # Convinience method to send mail with simply the subject
  def send_mail(subject: nil, template_path: nil, template_name: nil)
    # Change the subject if we have a custom notification
    if @custom_notification
      subject = @custom_notification.subject

      missing = missing_mandatory_attachment_names
      # Only bail out for a real notifier-driven send that we can actually record as skipped
      # (@notification present). Previews build no Notification — record_notification_skip
      # would be a no-op there anyway, so let previews render normally instead of going blank.
      if missing.present? && @notification
        record_notification_skip(missing)
        return
      end

      attach_custom_notification_documents
    end
    # send the email
    if @to.present?
      if template_path.present? && template_name.present?
        mail(from: @from, to: @to, cc: @cc, reply_to: @reply_to, subject:, template_path:, template_name:)
      else
        mail(from: @from, to: @to, cc: @cc, reply_to: @reply_to, subject:)
      end
    else
      msg = "No to email address, hence not sending any email"
      Rails.logger.info msg
      raise msg
    end
  end

  def password_protect_attachment(doc, model, custom_notification)
    doc.file.download do |source_file|
      dest_file = Rails.root.join("tmp/#{doc.id}.pdf").to_s
      # Get the password from the model based on the method specfied
      methods = custom_notification.attachment_password.split('.')
      password = methods.inject(model, &:send)
      # Execute the command - argv form avoids shell word-splitting on
      # passwords/paths containing spaces or shell metacharacters
      Rails.logger.info "Executing pdftk for document #{doc.id} with dest_file #{dest_file}"
      success = system("pdftk", source_file.path, "output", dest_file, "user_pw", password.to_s)
      raise "pdftk failed to password-protect document #{doc.id}" unless success && File.exist?(dest_file)

      # Return the file - Delete file post use in the caller
      File.new(dest_file)
    end
  end

  def pw_protect_attach_file(document, custom_notification)
    # Do we need to password protect the documents?
    file = if custom_notification&.password_protect_attachment
             password_protect_attachment(document, document.owner, custom_notification)
           else
             document.file
           end

    # Check for attachments
    attachments["#{document.name}.#{document.uploaded_file_extension}"] = file.read
    file.close
    File.delete(file) if file.instance_of?(::File)
  end

  # This is a generic method to send an email with a custom notification
  def adhoc_notification
    send_mail(subject: @custom_notification.subject, template_path: 'application_mailer', template_name: 'adhoc_notification')
  end

  # Hook for the shared adhoc_notification template to render a "View X" link,
  # gated by CustomNotification#show_link. Subclasses (CapitalCommitmentMailer,
  # FundInvestorKycMailer, ...) override this with their own record + URL; the
  # default is no link, so mailers that don't override it (e.g. DealMailer) keep
  # today's behavior unchanged.
  def adhoc_notification_link
    nil
  end
end
