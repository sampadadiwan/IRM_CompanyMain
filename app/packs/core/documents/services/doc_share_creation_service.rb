class DocShareCreationService < Trailblazer::Operation
  step :create_doc_share!
  step :send_email!

  def create_doc_share!(_ctx, doc_share:, **)
    doc_share.save
  end

  def send_email!(_ctx, doc_share:, **)
    # Send the email
    DocShareMailer.share_email(doc_share).deliver_later # Uncomment when mailer is ready
    # Update the doc_share to indicate that the email has been sent
    doc_share.update(email_sent: true)
    true
  end
end
