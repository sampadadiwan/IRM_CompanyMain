class EntityMailer < ApplicationMailer
  def notify_created
    @entity = Entity.find params[:id]
    mail(to: ENV.fetch('SUPPORT_EMAIL', nil),
         subject: "New Entity created #{@entity.name}")
  end

  def doc_gen_errors
    setup_defaults
    @error_msg = params[:error_msg]
    mail(from: @from, to: @to, cc: ENV.fetch("SUPPORT_EMAIL", nil), subject: "Errors")
  end

  def spa_job_errors
    @entity = Entity.find(params[:entity_id]) if params[:entity_id]
    @user = User.find(params[:user_id]) if params[:user_id]
    @from = from_email(@entity)
    @to = @entity.entity_setting.sandbox ? @entity.entity_setting.sandbox_emails : @user.email
    @error_msg = params[:error_msg]
    mail(from: @from, to: @to, cc: ENV.fetch("SUPPORT_EMAIL", nil), subject: "Errors")
  end

  def kpi_reminder
    @entity = Entity.find params[:entity_id]
    @requesting_entity = Entity.find params[:requesting_entity_id]
    @to ||= @entity.employees.pluck(:email).join(',')
    subject = "Reminder: KPIs requested by #{@requesting_entity.name}"
    send_mail(subject:)
  end
end
