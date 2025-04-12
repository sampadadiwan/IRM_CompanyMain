# The `ValueBridgeService` class is responsible for computing a "value bridge"
# that tracks changes in enterprise value across specific financial metrics
# (e.g., Revenue, EBITDA Margin, Valuation Multiple) between two valuation dates:
# the investment date and the analysis date.
# The value bridge provides a step-by-step breakdown of how each metric contributes
# to the change in enterprise value over time.

# Constants:
# - `VALUE_BRIDGE_FIELDS`: Defines the key financial metrics used to compute the value bridge.
# - `KEY_FIELDS`: Defines additional fields that may be relevant for calculations.

# Methods:
# - `initialize(investment_date_valuation, analysis_date_valuation)`:
#   Initializes the service with two valuation objects: one for the investment date
#   and one for the analysis date.
#
# - `compute_bridge`:
#   Computes the value bridge by iteratively adjusting each financial metric
#   in the valuation and calculating the resulting enterprise value change.
#   The method returns a hash where each key represents a step in the bridge
#   (e.g., "Entry", "Revenue", "EBITDA Margin", etc.), and the value is the
#   corresponding valuation object at that step.

class ValueBridgeService
  VALUE_BRIDGE_FIELDS = ["Revenue", "EBITDA Margin", "Valuation Multiple"].freeze
  KEY_FIELDS = ["Revenue", "EBITDA Margin", "EBITDA", "Valuation Multiple", "Enterprise Value", "Enterprise Value Change"].freeze

  def initialize(investment_date_valuation, analysis_date_valuation, value_bridge_fields = VALUE_BRIDGE_FIELDS)
    @investment_date_valuation = investment_date_valuation
    @analysis_date_valuation = analysis_date_valuation
    @value_bridge_fields = value_bridge_fields.presence || VALUE_BRIDGE_FIELDS
  end

  # Example Input:
  # investment_date_valuation = Valuation.new(
  #   json_fields: {
  #     "revenue" => 100,
  #     "ebitda_margin" => 20,
  #     "valuation_multiple" => 10,
  #     "enterprise_value" => 200
  #   }
  # )
  # analysis_date_valuation = Valuation.new(
  #   json_fields: {
  #     "revenue" => 120,
  #     "ebitda_margin" => 25,
  #     "valuation_multiple" => 12,
  #     "enterprise_value" => 360
  #   }
  # )
  # service = ValueBridgeService.new(investment_date_valuation, analysis_date_valuation)
  # result = service.compute_bridge

  # Example Output: Just dummy values here
  # {
  #   "Entry" => {
  #     "revenue" => 100,
  #     "ebitda_margin" => 20,
  #     "valuation_multiple" => 10,
  #     "enterprise_value" => 200,
  #     "enterprise_value_change" => nil
  #   },
  #   "Revenue" => {
  #     "revenue" => 120,
  #     "ebitda_margin" => 20,
  #     "valuation_multiple" => 10,
  #     "enterprise_value" => 240,
  #     "enterprise_value_change" => 40
  #   },
  #   "EBITDA Margin" => {
  #     "revenue" => 120,
  #     "ebitda_margin" => 25,
  #     "valuation_multiple" => 10,
  #     "enterprise_value" => 300,
  #     "enterprise_value_change" => 60
  #   },
  #   "Valuation Multiple" => {
  #     "revenue" => 120,
  #     "ebitda_margin" => 25,
  #     "valuation_multiple" => 12,
  #     "enterprise_value" => 360,
  #     "enterprise_value_change" => 60
  #   },
  #   "Exit" => {
  #     "revenue" => 120,
  #     "ebitda_margin" => 25,
  #     "valuation_multiple" => 12,
  #     "enterprise_value" => 360,
  #     "enterprise_value_change" => nil
  #   }
  # }
  def compute_bridge
    bridge = {}
    bridge["Entry"] = @investment_date_valuation
    prev_valuation = @investment_date_valuation.dup
    @value_bridge_fields.each do |bridge_field|
      # Start from the prev valuation
      valuation = prev_valuation.dup
      bridge_field_name = FormCustomField.to_name(bridge_field)
      # Set te value of the bridge field in the current valuation to the value of the analysis date valuation
      valuation.json_fields[bridge_field_name] = @analysis_date_valuation.json_fields[bridge_field_name]
      # Perform all calculations
      valuation.perform_all_calculations
      # Calculate the enterprise value change
      valuation.json_fields["enterprise_value_change"] = (valuation.json_fields["enterprise_value"] - prev_valuation.json_fields["enterprise_value"]).round(2) if valuation.json_fields["enterprise_value"].present? && prev_valuation.json_fields["enterprise_value"].present?
      # Add the valuation to the bridge
      bridge[bridge_field] = valuation
      # Set the prev valuation to the current valuation
      prev_valuation = valuation
    end
    bridge["Exit"] = @analysis_date_valuation
    bridge
  end
end
