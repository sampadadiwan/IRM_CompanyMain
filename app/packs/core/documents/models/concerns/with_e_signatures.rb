module WithESignatures
  extend ActiveSupport::Concern

  included do
    # Document can have many e_signatures attached
    has_many :e_signatures, as: :owner, dependent: :destroy
    has_many :stamp_papers, as: :owner, dependent: :destroy
    # Template can be setup with e_signatures required for generated docs
    accepts_nested_attributes_for :e_signatures, :stamp_papers, allow_destroy: true
    validates_associated :e_signatures, :stamp_papers
  end

  def esign?
    e_signatures.any?
  end

  # This gets called from the document generator, and returns the e_signatures for the document, based on the e_signatures in the template and data in the model
  # The e_signature in the template document is just a placeholder with a label
  # The e_signature in the generated document is the actual e_signature, with the user who needs to sign
  # The model must have a method with the same name as the label in the e_signature, which returns the user who needs to sign. Ex - if the e_signature label is "Buyer", then the model must have a method called "buyer" which returns the user who needs to sign
  def e_signatures_for(model)
    if esign? && model
      e_signatures.map do |e_signature|
        es = e_signature.dup
        method = e_signature.label.delete(' ').underscore
        if model.respond_to?(method)
          es.user = model.send(method)
        else
          es.user = User.where(email: e_signature.notes).last
          es.notes += " Invalid email, user not found." unless es.user
        end
        es
      end
    end
  end

  def stamp_papers_for(model)
    stamp_papers.map(&:dup) if stamp_papers && model
  end

  # This can be called from the controller to send the document for e-signing
  def send_for_esign(force: false, user_id: nil)
    if signature_enabled
      Rails.logger.debug { "Signature enabled for #{name}, sending for e-signing" }
      if !sent_for_esign || force
        Rails.logger.debug { "Sending #{name} #{id} for e-signing" }
        # Tell the provider to send it for e-signing
        DigioEsignJob.perform_later(id, user_id)
        true
      else
        Rails.logger.debug { "Document #{name} #{id} already queued for e-signing" }
        false
      end
    else
      Rails.logger.debug { "Signature not enabled for #{name}" }
      false
    end
  end

  # called by the provider once esign is completed
  def signature_completed(signed_doc_from_provider, replace: false)
    if replace
      # We replace the file in the orig document
      self.file = File.open(signed_doc_from_provider, "rb")
      self.owner_tag = "Signed"
      save
    else
      update(esign_status: "Completed")
      # We create a new document, and leave the old one intact.
      signed_doc = Document.new(attributes.slice("entity_id", "name", "orignal", "download", "printing", "user_id"))
      signed_doc.file = File.open(signed_doc_from_provider, "rb")
      signed_doc.from_template = self
      signed_doc.owner = owner
      signed_doc.owner_tag = "Signed"
      signed_doc.send_email = false
      signed_doc.locked = true
      signed_doc.save
    end
  end
end
