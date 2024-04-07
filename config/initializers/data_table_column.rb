# config/initializers/ajax_datatables_rails_monkey_patch.rb

module AjaxDatatablesRails
  module Datatable
    class Column
      # Redefine the validate_settings! method
      def validate_settings!
        raise AjaxDatatablesRails::Error::InvalidSearchColumn, "Unknown column. Check that `data` field is filled on JS side with the column name" if column_name.empty?

        unless column_name.to_s.index("custom_fields")
          raise AjaxDatatablesRails::Error::InvalidSearchColumn, "Check that column '#{column_name}' exists in view_columns" unless valid_search_column?(column_name)
          raise AjaxDatatablesRails::Error::InvalidSearchCondition, cond unless valid_search_condition?(cond)
        end
      end
    end
  end
end
