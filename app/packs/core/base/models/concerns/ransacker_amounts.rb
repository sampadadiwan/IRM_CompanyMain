module RansackerAmounts
  extend ActiveSupport::Concern

  included do
    %w[collected_amount committed_amount distribution_amount call_amount capital_fee other_fee amount cost_of_sold fmv gain carry cost_of_investment fee gross_amount net_amount reinvestment].each do |field|
      ransacker field.to_sym, formatter: proc { |v| v.to_d } do |_parent|
        Arel.sql("#{table_name}.#{field}_cents / 100.0")
      end
    end

    # This is just a sample for json fields
    ransacker :custom_field do |parent|
      Arel::Nodes::InfixOperation.new('->>', parent.table[:json_fields],
                                      Arel::Nodes.build_quoted('$.custom_field'))
    end
  end
end
