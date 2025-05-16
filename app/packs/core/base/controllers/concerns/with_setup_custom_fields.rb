module WithSetupCustomFields
  extend ActiveSupport::Concern

  private

  def setup_custom_fields(model, type: nil, force_form_type: nil)
    # I a few cases we need to force the form type Ex SecondarySale, Offer, Interest
    form_type = force_form_type

    # If the form type is not forced, we will try to find the form type based on the type
    form_type ||= if type.present?
                    FormType.where(entity_id: model.entity_id, name: type).last
                  else
                    FormType.where(entity_id: model.entity_id, name: model.class.name).last
                  end

    # set the models form type
    model.form_type = form_type
  end

  def setup_doc_user(model)
    sym = model.class.name.underscore.to_sym
    if params[sym][:documents_attributes].present?
      params[sym][:documents_attributes].each_value do |doc_attribute|
        doc_attribute[:user_id] = current_user.id
        doc_attribute.merge!(entity_id: model.entity_id)
      end
    end

    # For some reason the code above does not work for new records
    # hack for now
    if model.new_record?
      model.documents.each do |doc|
        doc.user_id = current_user.id
      end
    end
  end
end
