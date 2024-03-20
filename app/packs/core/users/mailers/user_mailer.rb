class UserMailer < ApplicationMailer
  def magic_link
    @user = User.find params[:id]
    @current_entity = Entity.where(id: params[:current_entity_id]).first if params[:current_entity_id].present?

    mail(from: from_email(@user.entity),
         to: @user.email,
         subject: "Login Link: Expires in 5 minutes")
  end
end
