class OfferPolicy < SaleBasePolicy
  # H19: what a seller (or their RM) fills in on the offer wizard: quantity, price, PAN, bank,
  # address, signatories and documents
  PARTICIPANT_ATTRIBUTES = %i[secondary_sale_id price completed quantity percentage notes full_name PAN address
                              bank_account_number bank_name ifsc_code city demat comments form_type_id acquirer_name
                              bank_routing_info id_proof address_proof spa seller_signatory_emails].freeze
  # H19: the selling firm's workflow fields. `verified` flipping on also queues OfferSpaJob, so a
  # seller sending it verified their own offer and generated its SPA.
  FIRM_ATTRIBUTES = %i[user_id entity_id verified allocation_quantity interest_id].freeze

  def index?
    user.enable_secondary_sale
  end

  delegate :create?, :show?, :new?, :update?, :edit?, :destroy?, :approve?, :accept_spa?, :generate_docs?, :bulk_actions?, :accept_spa, :matched_interests?, to: :specific_policy

  # H19: the fields this user may send, in the InvestorKycPolicy pattern. The firm's own users
  # (firm_side?, on SaleBasePolicy) send everything; sellers and RMs only the participant fields, so
  # workflow flags they post are dropped. investor_id - whose offer it is - comes from an RM's client
  # picker, and from a seller only on a new offer, where create? checks it is their own investor
  # at this sale's firm; a seller can never move a saved offer to another investor.
  # Tests H19-1, H19-3, H19-H — features/security/secondaries_isolation.feature
  def permitted_attributes
    fields = PARTICIPANT_ATTRIBUTES.dup
    # Whose offer: the firm and RMs pick it; a seller names it only when creating
    fields << :investor_id if firm_side? || rm? || new_offer?
    # The firm's workflow flags
    fields += FIRM_ATTRIBUTES if firm_side?
    fields + [{ docs_uploaded_check: {}, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {} }]
  end

  private

  # The controller asks with the class (create / new) or with the saved offer (update)
  def new_offer?
    record.is_a?(Class) || record.new_record?
  end
end
