class ValueBridgeService
  VALUE_BRIDGE_FIELDS = ["Revenue", "EBITDA Margin", "Valuation Multiple"].freeze
  KEY_FIELDS = ["Revenue", "EBITDA Margin", "EBITDA", "Valuation Multiple", "Enterprise Value", "Enterprise Value Change"].freeze

  def initialize(investment_date_valuation, analysis_date_valuation)
    @investment_date_valuation = investment_date_valuation
    @analysis_date_valuation = analysis_date_valuation
  end

  def compute_bridge
    bridge = {}
    bridge["Entry"] = @investment_date_valuation
    prev_valuation = @investment_date_valuation.dup
    VALUE_BRIDGE_FIELDS.each do |bridge_field|
      # Start from the prev valuation
      valuation = prev_valuation.dup
      bridge_field_name = FormCustomField.to_name(bridge_field)
      # Set te value of the bridge field in the current valuation to the value of the analysis date valuation
      valuation.json_fields[bridge_field_name] = @analysis_date_valuation.json_fields[bridge_field_name]
      # Perform all calculations
      valuation.perform_all_calculations
      # Calculate the enterprise value change
      valuation.json_fields["enterprise_value_change"] = valuation.json_fields["enterprise_value"] - prev_valuation.json_fields["enterprise_value"] if valuation.json_fields["enterprise_value"].present? && prev_valuation.json_fields["enterprise_value"].present?
      # Add the valuation to the bridge
      bridge[bridge_field] = valuation
      # Set the prev valuation to the current valuation
      prev_valuation = valuation
    end
    bridge["Exit"] = @analysis_date_valuation
    bridge
  end
end
