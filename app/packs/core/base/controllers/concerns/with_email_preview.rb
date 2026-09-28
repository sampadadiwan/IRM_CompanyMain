# This concern provides a `preview` action for controllers to render email templates.
# It dynamically fetches the relevant resource, determines the appropriate mailer,
# builds the email, and renders it for preview.
#
# Flow:
# 1. Fetch and validate the resource based on controller name.
# 2. Set up the mailer class, email method, and custom notification ID.
# 3. Handle investor access and build the mail object.
# 4. Render the email preview or an error message.
# 5. Catch and log any errors during the process.
module WithEmailPreview
  extend ActiveSupport::Concern

  def preview
    # Step 1: Fetch and validate the resource (e.g., @user, @investor_kyc)
    resource = fetch_and_validate_resource

    # Step 2: Determine the mailer class, email method, and custom notification ID
    mailer_class, email_method, custom_notification_id = setup_mailer_and_method(resource)

    # Step 3: Handle investor access and build the mail object for preview
    handle_investor_access_and_build_mail(resource, mailer_class, email_method, custom_notification_id)
  rescue StandardError => e
    # Step 5: Handle any exceptions during the preview process
    @error_message = "Unable to preview email"
    Rails.logger.debug e.message
    Rails.logger.debug e.backtrace.join("\n")
    @exception_message = e.message
    render "/layouts/email_preview", layout: true
  end

  private

  # Fetches the resource instance variable based on the controller name
  # and raises an error if the resource is not found.
  def fetch_and_validate_resource
    resource_name = controller_name.singularize
    # Special handling for investor KYC resources
    resource_name = "investor_kyc" if %w[individual_kyc non_individual_kyc].include?(resource_name)
    instance_var = "@#{resource_name}"
    resource = instance_variable_get(instance_var)
    # Ensure the resource exists before proceeding
    raise "#{instance_var} is nil" if resource.nil?

    resource
  end

  # Determines the mailer class, email method, and custom notification ID
  # based on the resource and request parameters.
  def setup_mailer_and_method(resource)
    # Use provided email method or default to "notify_<resource_name>"
    email_method = params[:email_method].presence || "notify_#{resource_name(resource)}"
    custom_notification_id = params[:custom_notification_id]
    mailer_class = resolve_mailer_class(resource, email_method, custom_notification_id)

    [mailer_class, email_method, custom_notification_id]
  end

  # Handles investor access logic and builds the mail object for preview.
  # Renders the email preview or an error message based on investor access.
  def handle_investor_access_and_build_mail(resource, mailer_class, email_method, custom_notification_id)
    investor = resource.try(:investor)
    @investor_access = investor&.investor_accesses&.approved&.first

    if @investor_access.present?
      # Build the mail object with required parameters for the mailer
      mail = mailer_class
             .with(
               "#{resource_name(resource)}_id": resource.id,
               email_method:,
               custom_notification_id:,
               user_id: @investor_access.user_id,
               entity_id: resource.try(:entity_id),
               # Only meaningful for FundInvestorKycMailer today (InvestorKyc has no single
               # owning fund, so it can't be derived from the resource itself) — every other
               # mailer simply doesn't read this param, so passing it through is harmless.
               fund_id: params[:fund_id]
             )
             .public_send(email_method)

      # Extract HTML body, attachments, and subject from the mail object
      html_part = mail.html_part || mail
      @html_body = html_part.body.decoded
      @attachments = mail.attachments
      @subject = mail.subject
      @oversized_attachments = oversized_preview_attachments(resource, custom_notification_id, mail)
      @attachment_documents = preview_attachment_documents(resource, custom_notification_id, mail)

      # Render the email preview without layout
      render "/layouts/email_preview", layout: false
    else
      # If no approved access, display an informative error message
      @error_message = "No approved investor access found for this user"
      Rails.logger.debug @error_message
      render "/layouts/email_preview", layout: true
    end
  end

  # Documents this email would carry that are over the size limit, so the preview can say so.
  #
  # Without this the preview is actively misleading: ApplicationMailer#attachment_allowed?
  # refuses an oversized document, and send_mail deliberately does NOT blank a preview
  # (there is no Noticed::Notification to record a skip against, and hiding the body would
  # defeat the point). The document simply vanishes from the attachment list - identical to
  # what an attachment_names pattern that matched nothing looks like. Preview is exactly where
  # an admin checks "will this attach the right file?", so that ambiguity matters.
  #
  # `resource` is the right owner to resolve against: every mailer that overrides
  # custom_notification_documents_owner returns this same record
  # (CapitalCommitmentMailer -> @capital_commitment, FundInvestorKycMailer -> @investor_kyc),
  # and the base implementation returns @notification&.model, which in a real send IS that
  # record. It is nil only in a preview, which is why the preview has to pass it explicitly.
  #
  # Uses violation_details rather than checking each document alone, so the RUNNING TOTAL rule
  # is covered too: several documents that each fit but together exceed the limit are refused
  # by the mailer, and a per-document check would report nothing at all for them.
  #
  # Scoped to the CustomNotification's own documents plus its attachment_names matches, in that
  # resolver's own order - which is exactly the list ApplicationMailer#attach_custom_notification_
  # documents iterates. Deliberately does NOT add the record's other documents: most notification
  # mailers (CapitalCommitmentMailer, the KYC mailers) have no attach_all_files, so folding those
  # in injects files the mailer never attaches, shifts the running total, and names the wrong
  # document. A running-total scenario caught exactly that.
  #
  # The cost is that a mailer which DOES auto-attach (CapitalRemittanceMailer,
  # CapitalDistributionPaymentsMailer, ApprovalMailer) has its generated notice unchecked in the
  # preview. Covering it needs per-mailer knowledge here, which is the drift this whole design
  # avoids; the batch preflight and the send-time guard both still stop those sends.
  #
  # Filtered against what actually got attached, so a document that fitted is never named.
  #
  # Returns one hash per refused document - see #describe_violations - because the warning links
  # the name to the file. An oversized document is the one thing in this preview NOT reachable
  # through the attachment list, so without that link the admin is told a file is too big and
  # left to go and find it.
  def oversized_preview_attachments(resource, custom_notification_id, mail)
    custom_notification = CustomNotification.find_by(id: custom_notification_id)
    candidates = NotificationAttachmentPreflight.custom_notification_documents(custom_notification, resource)
                                                .compact.uniq

    # Compared on the name WITHOUT its extension: attachments are filed as
    # "<name>.<ext>" while a violation detail carries the bare document name.
    attached = mail.attachments.map { |a| a.filename.to_s.sub(/\.[^.]*\z/, "") }
    details = NotificationAttachmentPreflight.violation_details(candidates)
    # Paired BEFORE the attached filter, so dropping a line cannot shift the pairing of the ones
    # that remain.
    describe_violations(details, candidates).reject { |problem| attached.include?(problem[:name]) }
  rescue StandardError => e
    # A warning that cannot be computed must never take down the preview itself.
    Rails.logger.warn("oversized_preview_attachments failed: #{e.message}")
    []
  end

  # Each violation with the Document it is about, so the warning can link to the file.
  #
  # A detail carries only the document's NAME. That is deliberate in the preflight - the same
  # hashes travel through a 137-recipient batch send, where holding a record per violation is
  # retention nobody asked for - so the pairing is done here, where there are at most a handful.
  #
  # violation_details walks `candidates` in order and keeps the ones it refuses, so the details
  # are a SUBSEQUENCE of that list: consuming a matching name as each detail is paired recovers
  # the exact record even when several documents share a name. That is the running-total case -
  # three identically named files, one of which tips the total - where matching by name alone
  # would link every line to whichever came first.
  #
  # :message is the unchanged one-line form, used when there is no document to link (a name that
  # no longer resolves). :rest is that sentence minus its leading name, so the name becomes the
  # link text and the rendered wording still reads exactly as the one-line form does everywhere
  # else - sentence_for's wording is asserted by features and already written to skip_reason
  # rows in production, so it is composed here rather than changed there.
  def describe_violations(details, candidates)
    remaining = candidates.dup
    details.map do |detail|
      name = detail[:document]
      index = remaining.index { |document| document.name == name }
      sentence = NotificationAttachmentPreflight.sentence_for(detail)

      { document: index.nil? ? nil : remaining.delete_at(index),
        name:,
        rest: sentence.delete_prefix(name),
        message: sentence }
    end
  end

  # The Document behind each attachment this email actually carries, keyed by the attachment's
  # filename, so the preview can link a listed attachment to the file itself.
  #
  # Preview exists to answer "will this attach the RIGHT file?", and a name on its own often
  # cannot: attachment_names resolves by pattern and `latest_doc_only` picks one of several
  # same-named documents, so the name the admin sees is exactly the part that is not in doubt.
  # Without a link the only way to check the contents is to trigger a real send.
  #
  # Matched on NotificationAttachmentPreflight.attachment_key - the same "<name>.<extension>"
  # ActionMailer files the part under (ApplicationMailer#attach_doc, #pw_protect_attach_file).
  # A key either equals a listed attachment's filename or is left unlinked; it never guesses.
  #
  # Looked up BY the names already on the message rather than by re-resolving what the mailer
  # would attach. That keeps it to a couple of rows on a table CLAUDE.md flags as very large
  # (auto_attached_documents would load every document on the record), and it needs no
  # per-mailer knowledge: an attachment is linkable if a document of that name exists on the
  # record, whichever code path put it there.
  #
  # Candidate order mirrors the mailer's attach order, and last-one-wins mirrors attachments[]
  # being a hash: the record's own documents oldest-first (attach_all_files runs in the mailer
  # action, before send_mail), then the CustomNotification's own (attach_custom_notification_
  # documents, inside it). So for two documents sharing a filename the link resolves to the
  # newest, and a CustomNotification upload beats a same-named document on the record - which
  # is the part the mailer would have attached last.
  #
  # A password-protected attachment (custom_notification.password_protect_attachment) is
  # encrypted on its way into the message; the link opens the stored original. That is the
  # document the admin is checking, not a copy of the encrypted part.
  def preview_attachment_documents(resource, custom_notification_id, mail)
    filenames = mail.attachments.map { |a| a.filename.to_s }
    return {} if filenames.empty?

    # attach_doc keys on "<name>.<ext>", so dropping the last extension yields the document
    # name back even when the name itself contains a dot.
    names = filenames.map { |filename| filename.sub(/\.[^.]*\z/, "") }.uniq
    candidates = []
    candidates += resource.documents.where(name: names).order(:created_at).to_a if resource.respond_to?(:documents)
    candidates += CustomNotification.find_by(id: custom_notification_id)&.documents.to_a

    candidates.each_with_object({}) do |document, map|
      key = NotificationAttachmentPreflight.attachment_key(document)
      map[key] = document if filenames.include?(key)
    end
  rescue StandardError => e
    # A link that cannot be resolved must never take down the preview itself - the list still
    # renders, just as plain text.
    Rails.logger.warn("preview_attachment_documents failed: #{e.message}")
    {}
  end

  # Renders the email preview template with the specified layout option.
  def render_email_preview(layout_option)
    render "/layouts/email_preview", layout: layout_option
  end

  # Determines the singularized resource name, with special handling for KYC types.
  def resource_name(resource)
    name = resource.class.name.underscore
    %w[individual_kyc non_individual_kyc].include?(name) ? "investor_kyc" : name
  end

  # Resolves the appropriate mailer class for a given resource.
  #
  # When a custom_notification_id is present, defer to CustomNotification's own
  # dispatch logic (mailer_class_for) instead of guessing from the resource's class
  # name — needed because the same resource type can route to different mailers
  # depending on email_method (e.g. an InvestorKyc resource resolves to
  # InvestorKycMailer for notify_kyc_required, but to FundInvestorKycMailer for
  # Fund's adhoc_kyc_notification — the class-name guess below only ever finds the
  # former). Falls back to the guessing logic below whenever no custom_notification_id
  # is given, or the lookup comes back empty — this keeps every existing preview
  # caller that never/rarely passes custom_notification_id (capital_remittances,
  # capital_distribution_payments, approval_responses) working unchanged.
  def resolve_mailer_class(resource, email_method = nil, custom_notification_id = nil)
    if custom_notification_id.present?
      resolved = CustomNotification.find_by(id: custom_notification_id)&.mailer_class_for(email_method)
      return resolved if resolved
    end

    # Tries several naming conventions to find the correct mailer.
    base = resource.class.name
    # Adjust base name for specific resource types
    base = "InvestorKyc" if %w[IndividualKyc NonIndividualKyc].include?(base)
    base = "Approval" if base == "ApprovalResponse"

    # Define potential mailer class name candidates
    candidates = [
      "#{base}Mailer",
      "#{base}sMailer",
      "#{base}NotificationMailer",
      "#{base}NotificationsMailer"
    ]

    # Iterate through candidates to find a valid mailer class
    candidates.each do |class_name|
      klass = class_name.safe_constantize
      return klass if klass
    end

    # Raise an error if no mailer class is found
    raise NameError, "Mailer class not found for #{base}"
  end
end
