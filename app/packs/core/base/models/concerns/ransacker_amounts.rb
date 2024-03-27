class RansackerAmounts < Module
  extend ActiveSupport::Concern

  def initialize(fields: {})
    super()
    @fields = fields
  end

  def included(base)
    fields = @fields
    base.class_eval do
      fields.each do |field|
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
end
