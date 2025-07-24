class Report < ApplicationRecord
  include WithGridViewPreferences

  belongs_to :entity, optional: true
  belongs_to :user

  attribute :template, :json

  after_save :add_report_id_to_url
  before_create :set_model

  include FileUploader::Attachment(:template_xls)

  validates :name, :curr_role, presence: true
  validates :category, length: { maximum: 30 }

  def self.reports_for
    { 'Account Entries': "/account_entries?filter=true",
      Commitments: "/capital_commitments?filter=true",
      Remittances: "/capital_remittances?filter=true",
      'Remittance Payments': "/capital_remittance_payments?filter=true",
      Kpis: "/kpis?filter=true",
      'Fund Units': "/fund_units?filter=true",
      KYCs: "/investor_kycs?filter=true",
      'Portfolio Investments': "/portfolio_investments?filter=true",
      'Aggregate Portfolio Investments': "/aggregate_portfolio_investments?filter=true",
      Distributions: "/capital_distributions?filter=true",
      'Distribution Payments': "/capital_distribution_payments?filter=true" }
  end

  # rubocop:disable Rails/SkipsModelValidations
  def add_report_id_to_url
    uri = URI.parse(url)
    return if uri.query.nil?

    query_params = CGI.parse(uri.query)
    # return if query_params['report_id']&.first == id.to_s

    query_params['report_id'] = id.to_s
    query_params['custom_xls_report'] = 'true' if template_xls.present? && metadata.present? && template.present?
    uri.query = URI.encode_www_form(query_params)
    update_column(:url, uri.to_s)
  end
  # rubocop:enable Rails/SkipsModelValidations

  # Adds parameters to the existing URL
  # This method modifies the URL in place. Used in DashboardWidgetsHelper.
  def add_params_to_url(params)
    uri = URI.parse(url)
    query_params = CGI.parse(uri.query || '')
    params.each do |key, value|
      query_params[key] = value.to_s
    end
    uri.query = URI.encode_www_form(query_params)
    self.url = uri.to_s
  end

  def decode_url
    uri = URI.parse(url)
    decoded_url = uri.path if uri.path
    decoded_url += "?#{CGI.unescape(uri.query)}" if uri.query.present?
    self.url = decoded_url
  end

  def model
    @model ||= url.split('?').first.delete_prefix('/').singularize.camelize
  end

  def set_model
    controller_name = url.split('?').first.delete_prefix('/')
    self.model = controller_name.singularize.camelize
  end

  def to_s
    name
  end

  def is_dynamic?
    uri = URI.parse(url)
    decoded_url = "?#{CGI.unescape(uri.query)}" if uri.query.present?
    decoded_url.include?("{") && decoded_url.include?("}")
  end

  def url_from(params)
    uri = URI.parse(url)

    # Extract the path and append /dynamic
    updated_path = uri.path

    # Decode and substitute parameters in query string
    substituted_query = if uri.query.present?
                          query = CGI.unescape(uri.query)
                          params.each do |key, value|
                            query = query.sub("{#{key}}", value.to_s)
                          end
                          query
                        end

    # Reconstruct the final URL
    final_url = if substituted_query.present?
                  "#{updated_path}?#{substituted_query}"
                else
                  updated_path
                end

    Rails.logger.debug { "Original URL: #{url}" }
    Rails.logger.debug { "Params: #{params}" }
    Rails.logger.debug { "Final URL: #{final_url}" }

    final_url
  end

  before_save :update_xls, if: :template_xls_changed?
  def update_xls
    if template_xls.present?
      template_xls.download do |tmp_file|
        json_data = XlsxToTemplate.convert(tmp_file.path)
        self.template = json_data.to_json
      end
    end
  end

  def template_xls_name
    template_xls.metadata["filename"] if template_xls.present?
  end

  def template_xls_mime_type
    template_xls.metadata["mime_type"] if template_xls.present?
  end

  def generate_xls(records)
    if template_xls.present? && template.present? && metadata.present?
      XlsxFromTemplate.generate_and_save(template, records, metadata, file_path: Rails.root.join('tmp', "export_#{id}_#{Time.now.to_i}.xlsx"))
    else
      raise "Template XLS or template or metadata is not set for this report."
    end
  end

  def stream_xls(records, filename: "report_#{id}_#{Time.now.to_i}.xlsx")
    if template_xls.present? && template.present? && metadata.present?
      XlsxFromTemplate.stream(template, records, metadata, filename: filename)
    else
      raise "Template XLS or template or metadata is not set for this report."
    end
  end
end
