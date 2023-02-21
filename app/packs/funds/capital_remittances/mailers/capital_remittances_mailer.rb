class CapitalRemittancesMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_remittance = CapitalRemittance.find params[:id]
    emails = sandbox_email(@capital_remittance, @capital_remittance.investor.emails)

    # Check for attachments
    @capital_remittance.documents.generated.each do |doc|
      attachments["#{doc.name}.pdf"] = doc.file.read
    end

    if emails.present?
      mail(from: from_email(@capital_remittance.entity),
           to: emails,
           subject: "Capital Call: #{@capital_remittance.entity.name}")
    end
  end
end
