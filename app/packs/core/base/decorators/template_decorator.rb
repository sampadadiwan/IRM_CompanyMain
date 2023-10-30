class TemplateDecorator < ApplicationDecorator
  def method_missing(method_name, *args, &)
    # This is to enable templates to get specific account entries
    if method_name.to_s.include?("account_entries_")
      account_entry_name = method_name.to_s.gsub("account_entries_", "").humanize.titleize
      aes = account_entries.where("account_entries.name=?", account_entry_name)
      return aes

    elsif method_name.to_s.include?("money_")
      attr_name = method_name.to_s.gsub("money_", "")
      return money_to_currency(send(attr_name))

    elsif method_name.to_s.include?("date_format_")
      attr_name = method_name.to_s.gsub("date_format_", "")
      return send(attr_name)&.strftime("%d %B %Y")

    elsif method_name.to_s.include?("format_")
      attr_name = method_name.to_s.gsub("format_", "")
      return h.number_with_delimiter(send(attr_name).to_d)

    elsif method_name.to_s.include?("rupees_")
      attr_name = method_name.to_s.gsub("rupees_", "")
      return send(attr_name).to_i.rupees.humanize

    elsif method_name.to_s.include?("dollars_")
      attr_name = method_name.to_s.gsub("dollars_", "")
      return send(attr_name).to_i.to_words.humanize
    end
    super
  end

  def respond_to_missing? *_args
    true
  end
end
