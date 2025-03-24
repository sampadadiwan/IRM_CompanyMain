class EntityMailer < ApplicationMailer
  def notify_created
    @entity = Entity.find params[:id]
    mail(to: ENV.fetch('SUPPORT_EMAIL', nil),
         subject: "New Entity created #{@entity.name}")
  end

  def doc_gen_errors
    setup_defaults
    add_support_to_cc
    @error_msg = params[:error_msg]
    subject = params[:subject].presence || "Errors"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end

  def spa_job_errors
    add_support_to_cc
    @error_msg = params[:error_msg]
    subject = params[:subject].presence || "Errors"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end

  def kpi_reminder
    @entity = Entity.find params[:entity_id]
    @requesting_entity = Entity.find params[:requesting_entity_id]
    @to ||= @entity.employees.pluck(:email).join(',')
    subject = "Reminder: KPIs requested by #{@requesting_entity.name}"
    send_mail(subject:)
  end

  def add_support_to_cc
    support_email = ENV.fetch('SUPPORT_EMAIL', nil)
    @cc.present? ? @cc += ",#{support_email}" : @cc = support_email
  end

  def notify_errors
    @error_msg = params[:error_msg]
    subject = params[:subject].presence || "Errors"
    mail(to: ENV.fetch('SUPPORT_EMAIL', nil), subject:)
  end
end
