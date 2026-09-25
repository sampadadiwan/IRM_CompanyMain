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
  def oversized_preview_attachments(resource, custom_notification_id, mail)
    custom_notification = CustomNotification.find_by(id: custom_notification_id)
    candidates = NotificationAttachmentPreflight.custom_notification_documents(custom_notification, resource)

    # Compared on the name WITHOUT its extension: attachments are filed as
    # "<name>.<ext>" while a violation detail carries the bare document name.
    attached = mail.attachments.map { |a| a.filename.to_s.sub(/\.[^.]*\z/, "") }
    NotificationAttachmentPreflight.violation_details(candidates).filter_map do |detail|
      next if attached.include?(detail[:document])

      NotificationAttachmentPreflight.sentence_for(detail)
    end
  rescue StandardError => e
    # A warning that cannot be computed must never take down the preview itself.
    Rails.logger.warn("oversized_preview_attachments failed: #{e.message}")
    []
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
