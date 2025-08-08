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
    mailer_class = resolve_mailer_class(resource)
    # Use provided email method or default to "notify_<resource_name>"
    email_method = params[:email_method].presence || "notify_#{resource_name(resource)}"
    custom_notification_id = params[:custom_notification_id]

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
               entity_id: resource.try(:entity_id)
             )
             .public_send(email_method)

      # Extract HTML body, attachments, and subject from the mail object
      html_part = mail.html_part || mail
      @html_body = html_part.body.decoded
      @attachments = mail.attachments
      @subject = mail.subject

      # Render the email preview without layout
      render "/layouts/email_preview", layout: false
    else
      # If no approved access, display an informative error message
      @error_message = "No approved investor access found for this user"
      Rails.logger.debug @error_message
      render "/layouts/email_preview", layout: true
    end
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
  # It tries several naming conventions to find the correct mailer.
  def resolve_mailer_class(resource)
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
