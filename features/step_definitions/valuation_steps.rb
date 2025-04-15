
Given('the valuation custom fields are filled out with {string}') do |args|
  valuation = Valuation.last
  hash = args.split(";").map { |pair| pair.split("=") }.to_h
  # Optionally, convert string values to numeric where applicable:
  hash.transform_values! { |v| v.include?(".") ? v.to_f : v.to_i }

  hash.each do |key, value|
    valuation.json_fields[key] = value
  end
  valuation.save
end

When('the value bridge is created between the two valuations') do
  @initial_valuation = Valuation.first
  @final_valuation = Valuation.last
  @value_bridge = ValueBridgeService.new(@initial_valuation, @final_valuation).compute_bridge
end

Then('I should see the value bridge details on the details page') do

  @value_bridge.each do |key, value|
    puts "#{key}: #{value.json_fields}"
  end

  # Assuming @value_bridge is a hash with keys that match the expected output
  @value_bridge.keys.should include("Entry", "Revenue", "EBITDA Margin", "Valuation Multiple", "Exit")

  current_valuation = @initial_valuation
  ValueBridgeService::VALUE_BRIDGE_FIELDS.each do |key|
    bridge_valuation = @value_bridge[key]
    # Copy the json_fields from the final valuation to the current valuation
    if ValueBridgeService::VALUE_BRIDGE_FIELDS.include?(key)
      bridge_field_name = FormCustomField.to_name(key)
      puts "Setting #{bridge_field_name} from #{current_valuation.json_fields[bridge_field_name]} to #{@final_valuation.json_fields[bridge_field_name]}"
      current_valuation.json_fields[bridge_field_name] = @final_valuation.json_fields[bridge_field_name]
      current_valuation.perform_all_calculations
    end

    # Check if the json_fields match
    current_valuation.json_fields.each do |field, field_value|
      puts "Checking field: #{key} #{field} #{bridge_valuation.json_fields[field]} with value: #{field_value}"
      bridge_valuation.json_fields[field].should == field_value
    end
    
  end



end