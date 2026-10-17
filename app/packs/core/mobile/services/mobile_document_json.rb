# Document fields the LP mobile app needs beyond the website's documents/_document.json:
# a list row, and — merged into GET /documents/:id.json — this user's signature status and what
# "Sign" should do (lp-mobile-app design card ④ "Signing").
module MobileDocumentJson
  module_function

  def summary(doc)
    { id: doc.id, name: doc.name, owner_type: doc.owner_type, owner_tag: doc.owner_tag,
      created_at: doc.created_at&.to_date }
  end

  def signing(doc, user)
    signature = doc.e_signatures.find { |esign| esign.user_id == user&.id }
    action = sign_action(doc, signature)
    { signature_status: signature&.status.presence, sign_action: action,
      sign_url: action == "digio_url" ? digio_signing_url(doc, signature) : nil }
  end

  # nil when this user has nothing to sign; otherwise how the app should let them sign:
  #   digio_url       open Digio's signing page in the app (H18)
  #   docusign_email  DocuSign only allows signing from its own email (E21)
  def sign_action(doc, signature)
    return nil if signature.nil? || signature.status == "signed" || !doc.sent_for_esign

    if doc.entity.entity_setting.esign_provider == "Docusign"
      "docusign_email"
    elsif doc.provider_doc_id.present?
      "digio_url"
    end
  end

  # Digio's hosted signing page for one signer of one document (its documented redirect flow:
  # /#/gateway/login/<document id>/<transaction id>/<signer identifier>). The sandbox and
  # production gateways mirror DIGIO_BASE_URL's environment; DIGIO_GATEWAY_URL overrides it.
  def digio_signing_url(doc, signature)
    gateway = ENV["DIGIO_GATEWAY_URL"].presence ||
              (ENV["DIGIO_BASE_URL"].to_s.include?("ext.digio.in") ? "https://ext.digio.in" : "https://app.digio.in")
    identifier = ERB::Util.url_encode(signature.email.presence || signature.user&.email)
    "#{gateway}/#/gateway/login/#{doc.provider_doc_id}/#{SecureRandom.hex(6)}/#{identifier}"
  end
end
