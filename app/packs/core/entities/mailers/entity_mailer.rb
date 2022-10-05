class EntityMailer < ApplicationMailer
  def notify_created
    @entity = Entity.find params[:id]

    mail(to: ENV['SUPPORT_EMAIL'],
         subject: "New Entity created #{@entity.name}")
  end
end
