class TemplateDecorator < ApplicationDecorator
  include CurrencyHelper

  METHODS_START_WITH = %w[compare_ where_ money_ date_format_ format_nd_ format_ rupees_ dollars_ list_ indian_words_ words_ sanitized_ boolean_custom_field_ sum_amt_ sum_ amt_].freeze

  def add_filter_clause(association, filter_field, filter_value)
    object.send(association).where("#{filter_field}=?", filter_value.to_s.tr("_", " ").humanize.titleize)
  end

  def custom_fields
    TemplateDecorator.new(object.custom_fields)
  end

  def method_missing(method_name, *args, &)
    # This is used in the template to hide/show sections based on sablon if
    # compare_category_eq_LP:if
    # The the category should be eq to LP for this to be true
    if method_name.to_s.starts_with?("compare_")
      params = method_name.to_s.gsub("compare_", "")
      filter_field, filter_value = params.split("_eq_")
      return send(filter_field)&.parameterize&.underscore == filter_value.downcase
    elsif method_name.to_s.starts_with?("where_")
      # This is used in the template to filter a collection based on a field
      # for example where_investor_name_eq_John
      # This will return a collection of objects where the investor_name is equal to John
      params = method_name.to_s.gsub("where_", "")
      filter_field, filter_value = params.split("_eq_")
      collection = object.where("#{filter_field}=?", filter_value.to_s.tr("_", " ").humanize)
      return TemplateDecorator.decorate_collection(collection)

    elsif method_name.to_s.starts_with?("money_")
      # This is used in the template to format a money attribute
      # for example money_investment_amount
      attr_name = method_name.to_s.gsub("money_", "")
      return money_to_currency(send(attr_name))

    elsif method_name.to_s.starts_with?("date_format_")
      # This is used in the template to format a date attribute
      # for example date_format_investment_date
      # It will return the date in the format of "dd Month yyyy"
      attr_name = method_name.to_s.gsub("date_format_", "")
      return send(attr_name)&.strftime("%d %B %Y")

    elsif method_name.to_s.starts_with?("format_nd_")
      # This is used in the template to format a number attribute without decimal places
      # for example format_nd_investment_amount
      # It will return the number with no decimal places and with a comma as a delimiter
      attr_name = method_name.to_s.gsub("format_nd_", "")
      return h.number_with_precision(send(attr_name).to_d, precision: 0, delimiter: ",")

    # if method_name starts_with "sum_amt_" && method name contains and or sub
    # then split the method name by _and_ and _sub_ and call sum on each part
    # and return the difference
    elsif method_name.to_s.starts_with?("sum_amt_") && method_name.match?(/_and_|_sub_/)
      method_name = method_name.to_s.gsub("sum_amt_", "")

      add_parts, sub_parts = method_name.split("_sub_").map { |part| part.split('_and_') }

      Rails.logger.debug ["add #{add_parts}", "sub #{sub_parts}"]

      # if object is an ActiveRecord::Relation, we need to call sum on each part for each object in the relation
      # and return the difference
      if object.is_a?(ActiveRecord::Relation)
        # if relation is empty, return 0.0
        return 0.0 if object.empty?

        add_values = add_parts.map { |attr| sum(attr.to_sym) }
        sub_values = sub_parts&.map { |attr| sum(attr.to_sym) } || []
      else
        # if object is not an ActiveRecord::Relation it is a singular object, we need to call send on each part
        add_values = add_parts.map { |attr| send(attr) }
        sub_values = sub_parts&.map { |attr| send(attr) } || []
      end

      # Final calculation
      # We determine the subunit to divide by so we can return the result in amount and not cents
      # Necessary as some Currenncies dont have a 100 subunit ie 100 cents make a dollar but for yen the subunit is 1 as they dont have a subunit
      subunit_to_unit = if object.is_a?(ActiveRecord::Relation)
                          object.first.send(add_parts.first.gsub("_cents", "").to_sym).currency.subunit_to_unit.to_d
                        else
                          object.send(add_parts.first.gsub("_cents", "").to_sym).currency.subunit_to_unit.to_d
                        end

      # Divide by sububit to return the amount
      return (add_values.sum - sub_values.sum) / subunit_to_unit

    elsif method_name.to_s.starts_with?("sum_amt_")
      attr_name = method_name.to_s.gsub("sum_amt_", "")
      return 0.0 if object.empty?

      # We determine the subunit to divide by so we can return the result in amount and not cents
      # Necessary as some Currenncies dont have a 100 subunit ie 100 cents make a dollar but for yen the subunit is 1 as they dont have a subunit
      subunit_to_unit = if object.is_a?(ActiveRecord::Relation)
                          object.first.send(attr_name.gsub("_cents", "").to_sym).currency.subunit_to_unit.to_d
                        else
                          object.send(attr_name.gsub("_cents", "").to_sym).currency.subunit_to_unit.to_d
                        end

      # Divide by sububit to return the amount
      return (sum(attr_name.to_sym) / subunit_to_unit)

    elsif method_name.to_s.starts_with?("sum_")
      attr_name = method_name.to_s.gsub("sum_", "")
      return 0.0 if object.empty?

      return sum(attr_name.to_sym)

    elsif method_name.to_s.starts_with?("format_")
      attr_name = method_name.to_s.gsub("format_", "")
      # return the attribute formatted with 2 decimal places
      return h.number_with_precision(send(attr_name).to_d, precision: 2, delimiter: ",")

    elsif method_name.to_s.starts_with?("rupees_")
      attr_name = method_name.to_s.gsub("rupees_", "")
      return send(attr_name).to_i.rupees.humanize

    elsif method_name.to_s.starts_with?("dollars_")
      attr_name = method_name.to_s.gsub("dollars_", "")
      return send(attr_name).to_i.to_words.humanize

    elsif method_name.to_s.starts_with?("list_")
      attr_name = method_name.to_s.gsub("list_", "")
      return send(attr_name)&.join("; ")

    elsif method_name.to_s.starts_with?("indian_words_")
      attr_name = method_name.to_s.gsub("indian_words_", "")
      return send(attr_name).to_i.rupees.humanize

    elsif method_name.to_s.starts_with?("words_")
      attr_name = method_name.to_s.gsub("words_", "")
      return send(attr_name).humanize

    elsif method_name.to_s.starts_with?("sanitized_")
      attr_name = method_name.to_s.gsub("sanitized_", "")
      return send(attr_name)&.gsub(/\r?\n/, ' ').to_s
    elsif method_name.to_s.starts_with?("boolean_custom_field_")
      attr_name = method_name.to_s.gsub("boolean_custom_field_", "")
      return %w[true yes 1].include? custom_fields.send(attr_name).to_s.downcase
    end
    super
  rescue StandardError => e
    msg = "Error in TemplateDecorator #{method_name}: #{e.message}"
    Rails.logger.error { msg }
    raise msg
  end

  def respond_to_missing?(method_name, include_private = false)
    METHODS_START_WITH.any? { |prefix| method_name.to_s.starts_with?(prefix) } || super
  end
end
