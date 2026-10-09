class InvestorKycCreate < InvestorKycAction
  step :check_required_file_custom_fields # validate required File custom fields before save bypasses model validations
  step :save
  step :associate_with_owner
  left :handle_errors, Output(:failure) => End(:failure)
  step :fix_folder_paths
  step :send_kyc_form_on_create
  step :enable_kyc
  step :validate_bank
  step :validate_pan_card
  step :updated_notification
  step :journey_hook

  # Checks required File-type custom fields BEFORE save because company admins use save(validate:false),
  # which bypasses model validations. File fields store docs as Documents (not json_fields), so we
  # check the in-memory documents association rather than json_fields.
  # Skipped entirely when this is an interim/draft save (validate: false) — that flag exists precisely
  # so investors and fund employees can save partial KYCs and complete them later.
  def check_required_file_custom_fields(ctx, investor_kyc:, **)
    validate = ctx[:validate].nil? ? ctx[:investor_user] : ctx[:validate]
    return true unless validate

    # Use type_from_kyc_type to resolve the STI subclass name; class.name may still be InvestorKyc here
    # because setup_form_type / set_investor_name run in before_save, not before_validation.
    type_name = investor_kyc.respond_to?(:type_from_kyc_type) ? (investor_kyc.type_from_kyc_type || investor_kyc.class.name) : investor_kyc.class.name
    ft = investor_kyc.form_type || investor_kyc.entity&.form_types&.where(name: type_name)&.last
    return true if ft.blank?

    missing = ft.form_custom_fields.where(field_type: "File", required: true).reject do |fcf|
      document_name = fcf.label.presence || fcf.name.humanize
      investor_kyc.documents.any? { |d| d.name == document_name }
    end

    missing.each do |fcf|
      investor_kyc.errors.add(:base, "#{fcf.label.presence || fcf.name.humanize} can't be blank")
    end
    missing.empty?
  end

  # This method is used to generate the AML report for the investor_kyc
  def generate_aml_report(ctx, investor_kyc:, **)
    investor_kyc.generate_aml_report(ctx[:user_id]) if investor_kyc.full_name.present? && ctx[:user_id].present? && investor_kyc.entity.entity_setting.aml_enabled
    true
  end

  # This method is used to save the investor_kyc to the associated owner like capital_commitment or expression_of_interest
  def associate_with_owner(ctx, investor_kyc:, **)
    if ctx[:owner_id].present? && ctx[:owner_type].present?
      owner = ctx[:owner_type].constantize.find(ctx[:owner_id])
      owner.update_columns(investor_kyc_id: investor_kyc.id)
    end
    true
  end
  # rubocop:enable Rails/SkipsModelValidations
end
