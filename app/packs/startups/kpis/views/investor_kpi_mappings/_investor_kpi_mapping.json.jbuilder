# G22 (client onboarding): a KPI mapping over the API, so an imported mapping can be read back
json.extract! investor_kpi_mapping, :id, :entity_id, :investor_id, :import_upload_id, :form_type_id,
              :reported_kpi_name, :standard_kpi_name, :category, :data_type, :denomination, :position,
              :show_in_report, :base_for_common_size, :compute_formula, :autofill, :fx_conversion_method,
              :lower_threshold, :upper_threshold, :rag_comparator_tag, :rag_direction,
              :rag_green_threshold, :rag_red_threshold, :source_sheet, :created_at, :updated_at
# The portfolio company the mapping belongs to
json.investor_name investor_kpi_mapping.investor&.investor_name
json.custom_fields investor_kpi_mapping.json_fields
json.url investor_kpi_mapping_url(investor_kpi_mapping, format: :json)
