class UserMailer < ApplicationMailer
  def magic_link
    @user = User.find params[:id]

    mail(from: from_email(@user.entity),
         to: @user.email,
         subject: "Login Link: Expires in 5 minutes")
  end
end
