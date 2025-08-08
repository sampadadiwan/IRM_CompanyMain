class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SUPPORT_EMAIL", nil)
  layout "mailer"

  after_deliver :mark_delivered
  def mark_delivered
    begin
      # Lets update the notification to say we have sent the email with details
      # This is because if we have attachments, then we only want to body which is in mail.parts[0]

      db_mail_body = mail&.parts.present? ? mail.parts[0] : mail
    rescue StandardError
      db_mail_body = mail
    end

    # Save the email sent, subject and email details
    # rubocop:disable Rails/SkipsModelValidations
    @notification&.update_columns(
      email: { email: { to: @to, from: @from, cc: @cc, reply_to: @reply_to, params:, mail: db_mail_body } },
      email_sent: true,
      subject: message.subject.truncate(254)
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  # This will cause the to from and cc to be set from the entity and user
  # Note it will ensure that
  before_action :setup_defaults
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

  def setup_cc
    @cc = @entity.entity_setting.cc
    # Sometimes we have an ovveride for the cc field in the investor access
    investor_cc = @entity.investor_accesses.where(email: @user.email).first&.cc if @user
    if @user && (@cc.nil? || @cc.blank?) && investor_cc.present?
      @cc = investor_cc
    elsif @cc.present? && investor_cc.present?
      @cc += ",#{investor_cc}"
    end

    # Sometimes we have an ovveride for the cc field ex commitment specific cc
    if @additional_ccs
      @cc.present? ? @cc += ",#{@additional_ccs}" : @cc = @additional_ccs
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
    @current_entity.entity_setting.from_email.presence || ENV.fetch("SUPPORT_EMAIL", nil)
  end

  def attach_custom_notification_documents
    if @custom_notification && @custom_notification.documents.present?
      @custom_notification.documents.each do |document|
        attach_doc(document)
      end
    end

    if @custom_notification && @custom_notification.attachment_names.present? && @notification && @notification.model.respond_to?(:documents)
      @custom_notification.attachment_names.split(',').each do |name|
        # Get the document with the name from the model
        document = @notification.model.documents.where("name like ?", "%#{name}%").first
        # Attach it to the email
        attach_doc(document) if document.present?
      end
    end
  end

  def attach_doc(document)
    file = document.file
    # Add the file to the document
    attachments["#{document.name}.#{document.uploaded_file_extension}"] = file.read
    file.close
    # Cleanup
    File.delete(file) if file.instance_of?(::File)
  end

  # Convinience method to send mail with simply the subject
  def send_mail(subject: nil, template_path: nil, template_name: nil)
    # Change the subject if we have a custom notification
    if @custom_notification
      subject = @custom_notification.subject
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
      # Execute the command
      cmd = "pdftk #{source_file.path} output #{dest_file} user_pw #{password}"
      Rails.logger.info "Executing command: #{cmd}"
      system(cmd)
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
end
