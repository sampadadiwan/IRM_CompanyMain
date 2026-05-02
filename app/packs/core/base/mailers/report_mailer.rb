class ReportMailer < ApplicationMailer
  def scheduled_report(report, recipients, file_path)
    @report = report
    attachments[File.basename(file_path)] = File.binread(file_path)
    
    mail(
      to: recipients,
      subject: "Scheduled Report: #{@report.name}"
    )
  end
end
