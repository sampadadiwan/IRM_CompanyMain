class DocumentMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_new_document_to_investors
    @document = Document.find params[:id]

    if %w[Fund Deal SecondarySale InvestmentOpportunity].include? @document.owner_type
      investors = @document.investors_granted_access
      investors += @document.owner.investors_granted_access
    else
      investors = @document.access_rights.map(&:investor)
    end

    investors.uniq.compact.each do |investor|
      DocumentMailer.with(id: params[:id], investor_id: investor.id).notify_new_document.deliver_later
    end
  end

  def notify_new_document
    @document = Document.find params[:id]
    @investor = Investor.find(params[:investor_id])

    email_list = @investor.emails

    email = sandbox_email(@document, email_list.join(","))

    if email.present?
      subj = "New document #{@document.name} uploaded by #{@document.entity.name}"
      mail(from: from_email(@document.entity),
           to: email,
           subject: subj)
    else
      Rails.logger.debug { "No emails found for notify_new_document #{@document.name}" }
    end
  end

  def email_link
    @user = User.find(params[:user_id])
    @link = params[:link]

    email = sandbox_email(@user, @user.email)

    if email.present?
      subj = "Download link"
      mail(from: from_email(@user.entity),
           to: email,
           subject: subj)
    end
  end
end
