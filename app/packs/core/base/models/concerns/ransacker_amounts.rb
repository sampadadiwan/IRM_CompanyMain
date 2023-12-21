module RansackerAmounts
  extend ActiveSupport::Concern

  included do
    ransacker :collected_amount, formatter: proc { |v| v.to_d } do |_parent|
      Arel.sql("#{table_name}.collected_amount_cents / 100.0")
    end

    ransacker :committed_amount, formatter: proc { |v| v.to_d } do |_parent|
      Arel.sql("#{table_name}.committed_amount_cents / 100.0")
    end

    ransacker :distribution_amount, formatter: proc { |v| v.to_d } do |_parent|
      Arel.sql("#{table_name}.distribution_amount_cents / 100.0")
    end

    ransacker :call_amount, formatter: proc { |v| v.to_d } do |_parent|
      Arel.sql("#{table_name}.call_amount_cents / 100.0")
    end

    ransacker :amount, formatter: proc { |v| v.to_d } do |_parent|
      Arel.sql("#{table_name}.amount_cents / 100.0")
    end

    ransacker :capital_fee, formatter: proc { |v| v.to_d } do |_parent|
      Arel.sql("#{table_name}.capital_fee_cents / 100.0")
    end

    ransacker :other_fee, formatter: proc { |v| v.to_d } do |_parent|
      Arel.sql("#{table_name}.other_fee_cents / 100.0")
    end

    # This is just a sample for json fields
    ransacker :custom_field do |parent|
      Arel::Nodes::InfixOperation.new('->>', parent.table[:json_fields],
                                      Arel::Nodes.build_quoted('$.custom_field'))
    end
  end
end
