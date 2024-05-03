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
end
