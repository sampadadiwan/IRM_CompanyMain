class AddReportIdsToUrls < ActiveRecord::Migration[7.1]
  def change
    Report.find_each do |report|

      uri = URI.parse(report.url)
      next if uri.query.nil?

      query_params = CGI.parse(uri.query)
      query_params['report_id'] = report.id.to_s
      uri.query = URI.encode_www_form(query_params)
      report.update_column(:url, uri.to_s)
    end
  end
end
