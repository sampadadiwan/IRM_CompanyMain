class InterestPolicy < SaleBasePolicy
  # H19: what a buyer (or their RM) fills in on the interest wizard: quantity, price, PAN, bank,
  # address, contacts, signatories and documents
  PARTICIPANT_ATTRIBUTES = %i[secondary_sale_id quantity price completed comments details buyer_entity_name demat city
                              bank_account_number ifsc_code form_type_id address contact_name email PAN signature
                              buyer_signatory_emails].freeze
  # H19: the selling firm's workflow fields. final_agreement is set by the accept_spa operation, never
  # by a buyer's form; escrow_deposited is rendered only for the sale's firm.
  FIRM_ATTRIBUTES = %i[user_id entity_id verified final_agreement escrow_deposited allocation_quantity].freeze

  delegate :show?, :create?, :new?, :update?, :edit?, :destroy?, :generate_docs?, :short_list?, :matched_offers?, :accept_spa?, :matched_offer?, :owner?, :send_email_to_change?, to: :specific_policy

  def index?
    user.enable_secondary_sale
  end

  # H19: the fields this user may send, in the InvestorKycPolicy pattern. The firm's own users
  # (firm_side?, on SaleBasePolicy) send everything; buyers and RMs only the participant fields, so
  # workflow flags they post are dropped. investor_id comes from an RM's client picker, and from a
  # buyer only on a new interest (create? checks it is their own investor); a buyer can never move a
  # saved interest to another investor.
  # Tests H19-2, H19-H2 — features/security/secondaries_isolation.feature
  def permitted_attributes
    fields = PARTICIPANT_ATTRIBUTES.dup
    # Whose interest: the firm and RMs pick it; a buyer names it only when creating
    fields << :investor_id if firm_side? || rm? || new_interest?
    # The firm's workflow flags
    fields += FIRM_ATTRIBUTES if firm_side?
    fields + [{ documents_attributes: Document::NESTED_ATTRIBUTES, properties: {} }]
  end

  private

  # The controller asks with the class (create / new) or with the saved interest (update)
  def new_interest?
    record.is_a?(Class) || record.new_record?
  end
end
