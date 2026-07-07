class DocumentMailer < ApplicationMailer
  helper ApplicationHelper

  # kyc_full_name/folio_id/committed_amount branch on owner_type and go through owner directly,
  # rather than Document's scoped `investor_kyc`/`capital_commitment` belongs_to readers - those
  # readers run their type-guard as `where(documents: { owner_type: ... })`, which is only valid
  # when "documents" is already joined into the query. For a singular call like this (starting
  # from an already-loaded document), Rails builds a plain `InvestorKyc.find_by(id: owner_id)`/
  # `CapitalCommitment.find_by(id: owner_id)` query with that condition merged in - "documents"
  # was never joined, so it fails with "unknown column" every time, regardless of owner_type.
  # `owner` doesn't have this problem: it's a plain polymorphic belongs_to with no extra scope.
  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "document_name" => ->(m) { m.instance_variable_get(:@document)&.name },
    "kyc_full_name" => lambda { |m|
      document = m.instance_variable_get(:@document)
      case document&.owner_type
      when "InvestorKyc" then document.owner&.full_name
      when "CapitalCommitment" then document.owner&.investor_kyc&.full_name
      # Offer stores the signer's name directly (it's not fund-based, so there's no InvestorKyc).
      when "Offer" then document.owner&.full_name
      # Interest has no full_name of its own or a direct investor_kyc link - go via its investor.
      when "Interest" then document.owner&.investor&.investor_kycs&.last&.full_name
      end
    },
    "folio_id" => lambda { |m|
      document = m.instance_variable_get(:@document)
      document.owner.folio_id if document&.owner_type == "CapitalCommitment"
    },
    "committed_amount" => lambda { |m|
      document = m.instance_variable_get(:@document)
      document.owner.committed_amount&.format if document&.owner_type == "CapitalCommitment"
    }
  ).freeze

  before_action :set_document
  def set_document
    @document = Document.find params[:document_id]
    @custom_notification = @document.entity.custom_notification(@notification.params[:email_method], custom_notification_id: @notification.params[:custom_notification_id])
  end

  def notify_new_document
    subject = "#{@document.name} uploaded by #{@document.entity.name}"
    send_mail(subject:)
  end

  def send_document
    subject = "#{@document.name} uploaded by #{@document.entity.name}"
    # This password protects the file if required and attachs it
    pw_protect_attach_file(@document, @custom_notification)
    send_mail(subject:)
  end

  def email_link
    # Link will expire in 1 week
    @link = @document.file.url(expires_in: (60 * 60 * 24 * 7), response_content_disposition: "inline; filename=#{@document.name_with_extension}")
    @msg = params[:msg]
    subject = "Download link"
    send_mail(subject:)
  end
end
