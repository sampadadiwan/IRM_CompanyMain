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

    @filterable_custom_fields = register_filterable_ransackers_for(model_class)

    # Walk each ransackable association and register its filterable CF fields too.
    model_class.ransackable_associations.each do |assoc_name|
      assoc_class = model_class.reflect_on_association(assoc_name.to_sym)&.klass
      next unless assoc_class&.include?(WithCustomField)

      register_filterable_ransackers_for(assoc_class)
    end
  rescue NameError
    # controller_name.classify is not a model (e.g. dashboard controllers) — skip
    nil
  end

  # Loads filterable FCFs for one model class (union across all entity FormTypes,
  # deduped by name), registers a named ransacker on that class for each, and
  # returns the deduplicated list.
  def register_filterable_ransackers_for(model_class)
    form_types = FormType.where(entity_id: current_user.entity_id, name: model_class.name)
    all_filterable = FormCustomField
      .where(form_type: form_types)
      .filterable
      .order(:form_type_id, :position)

    deduped = all_filterable.index_by(&:name).values
    deduped.each { |fcf| model_class.register_cf_ransacker(fcf.name, label: fcf.human_label) }
    deduped
  end

  def filter_active?
    params[:filter].present? || params[:q].present?
  end
end
