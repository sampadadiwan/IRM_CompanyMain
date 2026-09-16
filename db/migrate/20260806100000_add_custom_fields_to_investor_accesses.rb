# LP CRM MVP (docs/modules/investors/lp_relationship_crm_alt_mvp_prd.md):
# InvestorAccess doubles as the "touch point" (contact) record for prospective LPs.
# All descriptive contact data (designation, POC role, intro, LinkedIn, primary flag)
# is tenant-configured via the existing WithCustomField machinery rather than
# dedicated columns — these two columns are the standard pair every model using
# WithCustomField carries (see tasks, investors, capital_commitments, ...).
class AddCustomFieldsToInvestorAccesses < ActiveRecord::Migration[8.1]
  def change
    # json_fields holds the custom-field values keyed by field name (aliased as
    # `properties` by WithCustomField). Nullable — existing rows simply have none.
    add_column :investor_accesses, :json_fields, :json unless column_exists?(:investor_accesses, :json_fields)

    # form_type_id points at the entity's FormType named "InvestorAccess";
    # WithCustomField#setup_form_type fills it in automatically on save.
    add_column :investor_accesses, :form_type_id, :bigint unless column_exists?(:investor_accesses, :form_type_id)
    add_index :investor_accesses, :form_type_id unless index_exists?(:investor_accesses, :form_type_id)
  end
end
