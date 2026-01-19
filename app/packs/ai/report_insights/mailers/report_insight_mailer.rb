class ReportInsightMailer < ApplicationMailer
  include MarkdownHelper

  before_action :set_report_insight
  def set_report_insight
    @report_insight = ReportInsight.find params[:report_insight_id]
  end

  def send_report_insight_link
    setup_defaults
    add_support_to_cc
    @to = params[:to].presence || @report_insight.report.fetch_recipient_emails
    subject = params[:subject] || "Report: #{@report_insight.report.name} has been generated"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end

  def add_support_to_cc
    support_email = ENV['SUPPORT_EMAIL_TO'].presence
    return unless support_email

    @cc = @cc.present? ? "#{@cc},#{support_email}" : support_email
  end

  def send_report_insight_summary
    setup_defaults
    add_support_to_cc

    @to = params[:to].presence || @report_insight.report.fetch_recipient_emails
    subject = params[:subject].presence || "Report: #{@report_insight.report.name} — Key Insights"

    @summary_html =
      (markdown_to_html(@report_insight.summary).to_s if @report_insight.summary.present?)

    mail(from: @from, to: @to, cc: @cc, subject:)
  end
end
