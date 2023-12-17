class EntityMailer < ApplicationMailer
  def notify_created
    @entity = Entity.find params[:id]

    mail(to: ENV.fetch('SUPPORT_EMAIL', nil),
         subject: "New Entity created #{@entity.name}")
  end

  def doc_gen_errors
    setup_defaults
    @error_msg = params[:error_msg]
    mail(from: @from, to: @to, subject: "Documentation Generation Errors")
  end
end
