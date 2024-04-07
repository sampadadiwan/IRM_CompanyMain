class ApplicationDatatable < AjaxDatatablesRails::ActiveRecord
  def sanitize_data(data)
    data.map do |record|
      if record.is_a?(Array)
        record.map { |td| ERB::Util.html_escape(td) }
      else
        record.update(record) { |k, v| k == :custom_fields ? v : ERB::Util.html_escape(v) }
      end
    end
  end
end
