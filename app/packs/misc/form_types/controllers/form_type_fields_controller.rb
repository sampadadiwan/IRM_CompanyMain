# ③④ The custom fields side panel on a record's page: loads the record's form type fields into the panel and saves
# every change at once. Form Types › Edit stays as it is.
# openspec/changes/grid-columns-inline-settings — design D14, D17; lld.md › Phase 3 contracts
class FormTypeFieldsController < ApplicationController
  before_action :load_record_and_form_type

  # GET /form_type_fields/settings?record_type=Investor&record_id=12 (from a record's page) or ?form_type_id=43
  # (from a form) — the panel body, inside "form_type_fields"
  def settings
    @fields = helpers.form_type_fields_rows(@form_type, current_user)
    render layout: false
  end

  # PATCH /form_type_fields/save — record_type + record_id or form_type_id, fields (JSON); nothing else is read (X17)
  def save
    result = FormTypeFieldsSave.call(user: current_user, form_type: @form_type, record: @record, fields: save_params[:fields])
    if result.success?
      # D16 — the saved marker: the panel controller refreshes the page in place
      render partial: "form_type_fields/saved", locals: { label: "#{helpers.form_type_fields_title(@model_class)} saved" }, layout: false
    else
      # X13, X14, X15 — the panel again, with the reasons and the list as submitted
      @errors = result.errors
      @fields = helpers.form_type_fields_rows_from_submission(@form_type, current_user, save_params[:fields])
      render :settings, layout: false, status: :unprocessable_content
    end
  end

  private

  # X18 — only a model of this app with custom fields; X12 — the record through the user's scope, and its show?;
  # X10, X11 — FormTypePolicy#inline_fields? on the form type its fields come from (company admin, not acting as
  # an investor)
  def load_record_and_form_type
    return load_form_type if save_params[:form_type_id].present?

    klass = ApplicationRecord.model_class_from_param(save_params[:record_type])
    raise ActiveRecord::RecordNotFound, "Unknown record type" unless klass&.include?(WithCustomField)

    @model_class = klass
    @record = policy_scope(klass).find(save_params[:record_id])
    authorize @record, :show?
    @form_type = FormTypeFieldsSave.form_type_for(@record)
    authorize @form_type, :inline_fields?
  end

  # From a form (new records included): the form type the form shows, through the user's scope, and the same
  # policy; its record type must have custom fields (X18). No record is linked.
  def load_form_type
    @form_type = policy_scope(FormType).find(save_params[:form_type_id])
    @model_class = ApplicationRecord.model_class_from_param(@form_type.name)
    raise ActiveRecord::RecordNotFound, "Unknown record type" unless @model_class&.include?(WithCustomField)

    @record = nil
    authorize @form_type, :inline_fields?
  end

  def save_params
    params.permit(:record_type, :record_id, :form_type_id, :fields)
  end
end
