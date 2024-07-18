class TemplateDecorator < ApplicationDecorator
  def add_filter_clause(association, filter_field, filter_value)
    object.send(association).where("#{filter_field}=?", filter_value.to_s.tr("_", " ").humanize.titleize)
  end

  def method_missing(method_name, *args, &)
    if method_name.to_s.include?("where_")
      params = method_name.to_s.gsub("where_", "")
      filter_field, filter_value = params.split("_eq_")
      collection = object.where("#{filter_field}=?", filter_value.to_s.tr("_", " ").humanize)
      return TemplateDecorator.decorate_collection(collection)

    elsif method_name.to_s.include?("money_")
      attr_name = method_name.to_s.gsub("money_", "")
      return money_to_currency(send(attr_name))

    elsif method_name.to_s.include?("date_format_")
      attr_name = method_name.to_s.gsub("date_format_", "")
      return send(attr_name)&.strftime("%d %B %Y")

    elsif method_name.to_s.include?("format_nd_")
      attr_name = method_name.to_s.gsub("format_nd_", "")
      return h.number_with_precision(send(attr_name).to_d, precision: 0, delimiter: ",")

    elsif method_name.to_s.include?("format_")
      attr_name = method_name.to_s.gsub("format_", "")
      return h.number_with_precision(send(attr_name).to_d, precision: 2, delimiter: ",")

    elsif method_name.to_s.include?("rupees_")
      attr_name = method_name.to_s.gsub("rupees_", "")
      return send(attr_name).to_i.rupees.humanize

    elsif method_name.to_s.include?("dollars_")
      attr_name = method_name.to_s.gsub("dollars_", "")
      return send(attr_name).to_i.to_words.humanize

    elsif method_name.to_s.include?("list_")
      attr_name = method_name.to_s.gsub("list_", "")
      return send(attr_name)&.join("; ")

    elsif method_name.to_s.include?("indian_words_")
      attr_name = method_name.to_s.gsub("indian_words_", "")
      return send(attr_name).to_i.rupees.humanize

    elsif method_name.to_s.include?("words_")
      attr_name = method_name.to_s.gsub("words_", "")
      return send(attr_name).humanize

    elsif method_name.to_s.include?("sanitized_")
      attr_name = method_name.to_s.gsub("sanitized_", "")
      return send(attr_name).gsub(/\r?\n/, ' ')

    end
    super
  rescue StandardError => e
    msg = "Error in TemplateDecorator #{method_name}: #{e.message}"
    Rails.logger.error { msg }
    raise msg
  end

  def respond_to_missing? *_args
    true
  end
end
