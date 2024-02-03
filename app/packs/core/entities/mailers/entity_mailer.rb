class EntityMailer < ApplicationMailer
  def notify_created
    @entity = Entity.find params[:id]
    mail(to: ENV.fetch('SUPPORT_EMAIL', nil),
         subject: "New Entity created #{@entity.name}")
  end

  def doc_gen_errors
    setup_defaults
    @error_msg = params[:error_msg]
    mail(from: @from, to: @to, subject: "Errors")
  end

  def kpi_reminder
    @entity = Entity.find params[:entity_id]
    @requesting_entity = Entity.find params[:requesting_entity_id]
    @to ||= @entity.employees.pluck(:email).join(',')
    subject = "Reminder: KPIs requested by #{@requesting_entity.name}"
    send_mail(subject:) if @to.present?
  end
end
