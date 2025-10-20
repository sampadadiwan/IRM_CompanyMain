class EntityMailer < ApplicationMailer
  def notify_created
    @entity = Entity.find params[:id]
    mail(to: ENV.fetch('SUPPORT_EMAIL', nil),
         subject: "#{ENV['BASE_DOMAIN']} New Entity created #{@entity.name}")
  end

  def doc_gen_errors
    setup_defaults
    add_support_to_cc
    @error_msg = params[:error_msg]
    subject = params[:subject].presence || "#{ENV['BASE_DOMAIN']} Errors"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end

  def spa_job_errors
    add_support_to_cc
    @error_msg = params[:error_msg]
    subject = params[:subject].presence || "#{ENV['BASE_DOMAIN']} Errors"
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
    subject = "#{ENV['BASE_DOMAIN']} #{params[:subject].presence || "Errors"}"
    to = params[:to].presence || ENV.fetch('SUPPORT_EMAIL', nil)
    mail(to:, subject:)
  end

  def notify_info
    @msg = params[:msg]
    subject = params[:subject].presence || "#{ENV['BASE_DOMAIN']} INFO"
    mail(to: ENV.fetch('SUPPORT_EMAIL', nil), subject:)
  end

  def send_report
    setup_defaults
    add_support_to_cc
    @report_data = begin
      JSON.parse(params[:report_data])
    rescue StandardError
      []
    end
    @title = "#{ENV['BASE_DOMAIN']} #{params[:subject].presence}"

    Rails.logger.info("[EntityMailer] Sending report email with #{@report_data.size} rows.")
    Rails.logger.debug(@report_data.inspect)

    mail(
      from: @from,
      to: @to,
      cc: @cc,
      subject: @title
    )
  end
end
