class DocShareMailer < ApplicationMailer
  def share_email(doc_share)
    @doc_share = doc_share
    token_service = DocShareTokenService.new
    @view_link = view_doc_shares_url(token: token_service.generate_token(@doc_share.id))
    mail(to: @doc_share.email, subject: "#{@doc_share.document.name} been shared with you")
  end
end
