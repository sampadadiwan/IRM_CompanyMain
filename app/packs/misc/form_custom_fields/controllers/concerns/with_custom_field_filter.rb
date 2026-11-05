module WithCustomFieldFilter
  extend ActiveSupport::Concern

  included do
    before_action :load_filterable_custom_fields, if: :filter_active?
  end

  private

  # Registers filterable custom field ransackers on the primary model and on every
  # ransackable association that also includes WithCustomField. This ensures that
  # fields like Investor.founder appear in the "Investor" group of the attribute
  # dropdown when filtering CapitalCommitments.
  def load_filterable_custom_fields
    model_class = controller_name.classify.constantize
    return unless model_class.include?(WithCustomField)

    # The primary model plus each ransackable association that also has custom fields
    assoc_classes = model_class.ransackable_associations.filter_map do |assoc_name|
      assoc_class = model_class.reflect_on_association(assoc_name.to_sym)&.klass
      assoc_class if assoc_class&.include?(WithCustomField)
    rescue NameError
      # An association whose class can't be resolved is skipped; the rest still register
      nil
    end

    # One query for every class's filterable fields, instead of one per association (N+1)
    fields_by_model = filterable_custom_fields_by_model([model_class, *assoc_classes].map(&:name).uniq)

    @filterable_custom_fields = register_filterable_ransackers_for(model_class, fields_by_model)
    assoc_classes.each { |assoc_class| register_filterable_ransackers_for(assoc_class, fields_by_model) }
  rescue NameError
    # controller_name.classify is not a model (e.g. dashboard controllers) — skip
    nil
  end

  # { model name => [filterable FCFs] } across all of this company's FormTypes for those models,
  # in form_type_id, position order. form_type_name comes back on each row so they can be grouped.
  def filterable_custom_fields_by_model(model_names)
    FormCustomField.joins(:form_type)
                   .where(form_types: { entity_id: current_user.entity_id, name: model_names })
                   .filterable
                   .order(:form_type_id, :position)
                   .select("form_custom_fields.*, form_types.name AS form_type_name")
                   .group_by(&:form_type_name)
  end

  # Registers one model class's filterable FCFs (union across all entity FormTypes, deduped by
  # name) on that class as THIS company's filter fields (replacing its previous set), and returns
  # the deduplicated list.
  def register_filterable_ransackers_for(model_class, fields_by_model)
    deduped = Array(fields_by_model[model_class.name]).index_by(&:name).values
    model_class.register_cf_ransackers(current_user.entity_id, deduped)
    deduped
  end

  def filter_active?
    params[:filter].present? || params[:q].present?
  end
end
