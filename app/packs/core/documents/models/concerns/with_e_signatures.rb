module WithESignatures
  extend ActiveSupport::Concern

  included do
    # Document can have many e_signatures attached
    has_many :e_signatures, as: :owner, dependent: :destroy
    # Template can be setup with e_signatures required for generated docs
    accepts_nested_attributes_for :e_signatures, allow_destroy: true
    validates_associated :e_signatures
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

  def stamp_paper?
    owner.respond_to?(:stamp_paper?) && owner&.stamp_paper?
  end

  def stamp_papers
    owner.stamp_papers if stamp_paper?
  end
end
