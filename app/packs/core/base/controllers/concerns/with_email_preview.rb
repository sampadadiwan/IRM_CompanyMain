module WithEmailPreview
  extend ActiveSupport::Concern

  def preview
    # Get the resource name from the controller (e.g., "users" -> "user")
    resource_name = controller_name.singularize
    resource_name = "investor_kyc" if %w[individual_kyc non_individual_kyc].include?(resource_name)

    # Build the instance variable name (e.g., "@user")
    instance_var = "@#{resource_name}"
    # Fetch the resource instance variable
    resource = instance_variable_get(instance_var)

    # Raise an error if the resource is not found
    raise "#{instance_var} is nil" if resource.nil?

    # Determine the mailer class for the resource (e.g., UserMailer)
    mailer_class = resolve_mailer_class(resource)
    # Default to "notify_<resource_name>" if no email_method is provided
    email_method = params[:email_method].presence || "notify_#{resource_name}"
    custom_notification_id = params[:custom_notification_id]

    # Try to get the associated investor and their approved access
    investor = resource.try(:investor)
    @investor_access = investor&.investor_accesses&.approved&.first

    if @investor_access.present?
      # Build the mail object with required parameters
      mail = mailer_class
             .with(
               "#{resource_name}_id": resource.id,
               email_method:,
               custom_notification_id:,
               user_id: @investor_access.user_id,
               entity_id: resource.try(:entity_id)
             )
             .public_send(email_method)

      # Get the HTML part of the email (or the mail itself if no multipart)
      html_part = mail.html_part || mail
      @html_body = html_part.body.decoded
      @attachments = mail.attachments
      @subject = mail.subject

      # Render the email preview without layout
      render "/layouts/email_preview", layout: false
    else
      # If no approved access, show an error message with layout
      @error_message = "No approved investor access found for this user"
      Rails.logger.debug @error_message
      render "/layouts/email_preview", layout: true
    end
  rescue StandardError => e
    # Handle any exceptions, show fallback or default error message
    @error_message = "Unable to preview email"
    Rails.logger.debug e.message
    Rails.logger.debug e.backtrace.join("\n")
    @exception_message = e.message
    render "/layouts/email_preview", layout: true
  end

  private

  def resolve_mailer_class(resource)
    base = resource.class.name
    base = "InvestorKyc" if %w[IndividualKyc NonIndividualKyc].include?(base)
    base = "Approval" if base == "ApprovalResponse"

    candidates = [
      "#{base}Mailer",
      "#{base}sMailer",
      "#{base}NotificationMailer",
      "#{base}NotificationsMailer"
    ]

    candidates.each do |class_name|
      klass = class_name.safe_constantize
      return klass if klass
    end

    raise NameError, "Mailer class not found for #{base}"
  end
end
