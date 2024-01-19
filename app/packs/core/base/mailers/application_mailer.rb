class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SUPPORT_EMAIL", nil)
  layout "mailer"

  # This will cause the to from and cc to be set from the entity and user
  # Note it will ensure that
  before_action :setup_defaults
  def setup_defaults
    @entity = Entity.find(params[:entity_id]) if params[:entity_id]
    @user = User.find(params[:user_id]) if params[:user_id]
    @additional_ccs ||= params[:additional_ccs]

    if @entity.present?
      # Ensure we pick te right from address
      @from = from_email(@entity)

      unless @entity.entity_setting.sandbox
        setup_cc
        @reply_to = @entity.entity_setting.reply_to.presence || @cc.presence || @from
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
    @current_entity = entity
    @current_entity.entity_setting.from_email.presence || ENV.fetch("SUPPORT_EMAIL", nil)
  end

  # Convinience method to send mail with simply the subject
  def send_mail(subject: nil)
    mail(from: @from, to: @to, cc: @cc, reply_to: @reply_to, subject:)
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
    attachments["#{document.name}.pdf"] = file.read
    file.close
    File.delete(file) if file.instance_of?(::File)
  end
end
