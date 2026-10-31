class ExpressionOfInterestPolicy < IoBasePolicy
  # H19: what an investor (or their RM) fills in on the EOI form: who it is for, the amount, the KYC,
  # the signatory, the details and documents
  PARTICIPANT_ATTRIBUTES = %i[investment_opportunity_id investor_id investor_kyc_id investor_name investor_email
                              amount investor_signatory_id details].freeze
  # H19: the opportunity firm's workflow fields - approval, verification, Data Room access and the
  # allocation - plus who the EOI belongs to
  FIRM_ATTRIBUTES = %i[entity_id user_id eoi_entity_id approved verified show_data_room allocation_percentage
                       allocation_amount comment].freeze

  def index?
    user.enable_inv_opportunities
  end

  def show?
    permissioned_employee? ||
      permissioned_investor? ||
      permissioned_rm?
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    (belongs_to_entity?(user, record) && parent_in_users_firms?(record.investment_opportunity)) ||
      permissioned_employee?(:create) ||
      permissioned_rm? || permissioned_investor?
  end

  def new?
    create?
  end

  def update?
    !record.approved &&
      (permissioned_employee?(:update) || permissioned_investor?)
  end

  def edit?
    update?
  end

  # For now we are disabling this
  def generate_documentation?
    false && update? && !record.esign_completed
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def approve?
    (permissioned_employee?(:update) || permissioned_investor?) && user.has_cached_role?(:approver)
  end

  # H19: allocating an EOI is the opportunity firm's decision. Was update?, which also admits the
  # investor, so an LP could allocate (and approve / verify) their own EOI.
  # Tests H19-5, H19-H3 — features/security/eoi_workflow_flags.feature
  def allocate?
    !record.approved && permissioned_employee?(:update)
  end

  def allocation_form?
    allocate?
  end

  # H19: the fields this user may send, in the InvestorKycPolicy pattern. Investors and RMs send the
  # participant fields only, so approval, allocation and Data Room flags they post are dropped.
  # Tests H19-4, H19-H3 — features/security/eoi_workflow_flags.feature
  def permitted_attributes
    fields = PARTICIPANT_ATTRIBUTES.dup
    # The firm's workflow flags
    fields += FIRM_ATTRIBUTES if firm_side?
    fields + [{ documents_attributes: Document::NESTED_ATTRIBUTES, properties: {} }]
  end

  # Staff of the opportunity's firm, never through a signed shared link
  def firm_side?
    return false if signed_id_access?

    # A saved EOI: update rights on its opportunity (support falls back inside permissioned_employee?)
    return permissioned_employee?(:update) if record.is_a?(ExpressionOfInterest) && record.persisted?

    # A new EOI (asked with the class): a fund-side user; create? then checks it is their opportunity
    !rm? && (user.curr_role == "employee" || support?)
  end
end
