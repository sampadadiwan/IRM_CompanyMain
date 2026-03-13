class UserMailer < ApplicationMailer
  def magic_link
    @user = User.find params[:id]
    @current_entity = Entity.where(id: params[:current_entity_id]).first if params[:current_entity_id].present?

    mail(from: from_email(@user.entity),
         to: @user.email,
         subject: "Login Link: Expires in 5 minutes")
  end

  def audit_download
    @user = User.find params[:user_id]
    attachments['audits.xlsx'] = { mime_type: 'application/xlsx', content: params[:file].read }
    mail(from: from_email(@user.entity),
         to: @user.email,
         subject: "Audit Download")
  end

  # Generic model download email
  # @param user_id [Integer] The user to send to
  # @param entity_id [Integer] The entity for branding
  # @param file [Tempfile] The file to attach
  # @param filename [String] The filename for the attachment
  def model_download
    @model_name = params[:model_name] || 'Model'
    filename = params[:filename] || 'download.xlsx'
    file = params[:document].file.download
    attachments[filename] = { mime_type: 'application/xlsx', content: file.read }
    subject = params[:message] || "Your Download is Ready: #{filename}"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end
end
