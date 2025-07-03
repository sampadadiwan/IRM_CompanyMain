# KPI RAG Status Computation (JSON Column Approach)

This document outlines the recommended approach for storing bucket ranges and computing RAG (Red, Amber, Green) status for KPIs, using a JSON column within the `InvestorKpiMapping` class. This approach allows RAG rules to be defined per `InvestorKpiMapping` instance, which is associated with a specific `kpi_standard_name`.

**Note:** `Kpi.name` is expected to match `InvestorKpiMapping.standard_kpi_name` for retrieving the relevant RAG rules.

## 1. Storing RAG Rules in `InvestorKpiMapping`

The RAG thresholds will be stored in a `json` column named `rag_rules` within the `InvestorKpiMapping` table. This allows for flexible, per-KPI-mapping configuration of RAG thresholds.

### Migration (if `rag_rules` column doesn't exist or needs to be `json`):

If your `investor_kpi_mappings` table does not already have a `rag_rules` column of type `json`, you would create a migration like this:

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_rag_rules_to_investor_kpi_mappings.rb
class AddRagRulesToInvestorKpiMappings < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kpi_mappings, :rag_rules, :json, default: {}
  end
end
```

Run `rails db:migrate` to apply this change.

### JSON Structure for `rag_rules`

The `rag_rules` JSON column will typically store the thresholds for different RAG statuses. A common structure for ratio-based RAG rules would be:

```json
{
  "ratio_rules": {
    "red": { "min": -Infinity, "max": 0.7 },
    "amber": { "min": 0.7, "max": 0.9 },
    "green": { "min": 0.9, "max": Infinity }
  },
  "absolute_rules": {
    // Optional: Add rules for absolute value comparisons if needed in the future
  }
}
```

**Explanation of JSON Fields:**
*   `ratio_rules`: Contains the RAG thresholds specifically for ratio-based comparisons.
*   `red`, `amber`, `green`: Keys representing the RAG statuses.
*   `min`, `max`: The numerical range for the ratio that corresponds to the specific RAG status.

### Example `InvestorKpiMapping` Data

You would populate the `rag_rules` column for each `InvestorKpiMapping` record, either manually, via seeds, or through an admin interface.

```ruby
# Example seed data for InvestorKpiMapping
InvestorKpiMapping.find_or_create_by!(standard_kpi_name: 'Employees', investor_id: 123) do |mapping|
  mapping.rag_rules = {
    "ratio_rules" => {
      "red" => { "min" => -Float::INFINITY, "max" => 0.7 },
      "amber" => { "min" => 0.7, "max" => 0.9 },
      "green" => { "min" => 0.9, "max" => Float::INFINITY }
    }
  }
end
```

## 2. Implement RAG Status Computation in `Kpi` Model

The logic to compute the RAG status will reside within the `Kpi` model (`app/packs/startups/kpis/models/kpi.rb`). It will retrieve the `rag_rules` from the relevant `InvestorKpiMapping` instance and use them to determine the status.

### `app/packs/startups/kpis/models/kpi.rb` additions:

```ruby
# Method to find the tagged KPI
def find_tagged_kpi(tag_list)
  Kpi.joins(:kpi_report)
     .where(
       name: name,
       portfolio_company_id: portfolio_company_id,
       'kpi_reports.as_of': kpi_report.as_of,
       'kpi_reports.tag_list': tag_list # Match by tag_list
     )
     .first
end

# Helper method to determine RAG status from rules
def determine_rag_status_from_rules(ratio, rules_hash, comparison_type: 'ratio_rules')
  return nil unless rules_hash.present? && rules_hash[comparison_type].present?

  rules = rules_hash[comparison_type]
  
  # Convert string keys to symbols for easier access if needed, or ensure consistency
  # rules = rules.transform_keys(&:to_sym) 

  # Sort rules by min bound to ensure correct order of evaluation
  sorted_rules = rules.values.sort_by { |r| r['min'] }

  sorted_rules.each do |rule|
    min_val = rule['min'] == '-Infinity' ? -Float::INFINITY : rule['min'].to_f
    max_val = rule['max'] == 'Infinity' ? Float::INFINITY : rule['max'].to_f

    if ratio >= min_val && ratio < max_val
      # Find the key (rag_status name) that corresponds to this rule's values
      return rules.key(rule)
    end
  end
  nil # No matching status found
end

# Method to compute and set RAG status
def set_rag_status_from_ratio(tagged_kpi_tag_list)
  tagged_kpi = find_tagged_kpi(tagged_kpi_tag_list)

  # Find the InvestorKpiMapping for this KPI's standard name
  # Kpi.name will match InvestorKpiMapping.standard_kpi_name
  investor_kpi_mapping = InvestorKpiMapping.find_by(standard_kpi_name: name)

  if tagged_kpi && tagged_kpi.value.present? && tagged_kpi.value != 0 && investor_kpi_mapping&.rag_rules.present?
    ratio = value.to_f / tagged_kpi.value.to_f
    self.rag_status = determine_rag_status_from_rules(ratio, investor_kpi_mapping.rag_rules, 'ratio')
  elsif tagged_kpi && tagged_kpi.value.present? && tagged_kpi.value == 0
    # Handle division by zero: perhaps set to 'red' or a specific status for this case
    self.rag_status = 'red' # Or 'N/A', 'undefined', based on business logic
  else
    self.rag_status = nil # Or a default status if tagged_kpi or rules are not found
  end
  save if changed? # Save the KPI if rag_status has been updated
end
```

### Usage Example:

To use this, you would call the `set_rag_status_from_ratio` method on a `Kpi` instance, providing the `tag_list` of the `tagged_kpi` you wish to compare against:

```ruby
my_kpi = Kpi.find(2103) # Example: your 'Employees' KPI instance
my_kpi.set_rag_status_from_ratio('benchmark') # Compare against a KPI with 'benchmark' tag
```

This revised approach leverages the `rag_rules` JSON column in `InvestorKpiMapping` to store and retrieve RAG thresholds, providing a flexible and integrated solution for KPI-specific RAG status computation.