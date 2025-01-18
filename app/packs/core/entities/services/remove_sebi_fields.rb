class RemoveSebiFields < SebiFieldsActions
  step :disable_sebi_fields
  step :remove_sebi_custom_fields_from_all_classes, Output(:failure) => End(:failure)
  step :save
  left :handle_errors, Output(:failure) => End(:failure)

  def disable_sebi_fields(_ctx, entity:, **)
    entity.permissions.unset(:enable_sebi_fields)
    entity.valid?
  end

  def remove_sebi_custom_fields_from_all_classes(ctx, entity:, **)
    ["InvestorKyc", "IndividualKyc", "NonIndividualKyc", "InvestmentInstrument"].each do |class_name|
      remove_custom_fields_to_form(ctx, class_name, entity)
    end
  end

  def remove_custom_fields_to_form(ctx, class_name, entity)
    form_type = FormType.find_by(name: class_name, entity_id: entity.id)
    return if form_type.blank?
    form_type.form_custom_fields.where(name: class_name.constantize::SEBI_REPORTING_FIELDS.keys).destroy_all
  end
end
