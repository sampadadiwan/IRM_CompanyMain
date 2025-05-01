class Report < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user
  has_many :grid_view_preferences, as: :owner, dependent: :destroy
  before_commit :add_report_id_to_url, unless: -> { destroyed? }
  before_create :set_model

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

  def add_report_id_to_url
    id
    uri = URI.parse(url)
    return if uri.query.nil?

    query_params = CGI.parse(uri.query)
    query_params['report_id'] = id.to_s
    uri.query = URI.encode_www_form(query_params)
    self.url = uri.to_s
    save!
  end

  def decode_url
    uri = URI.parse(url)
    decoded_url = uri.path if uri.path
    decoded_url += "?#{CGI.unescape(uri.query)}" if uri.query.present?
    self.url = decoded_url
  end

  def set_model
    path = ActiveSupport::HashWithIndifferentAccess.new(Report.reports_for)[category]
    return unless path

    controller_name = path.split('?').first.delete_prefix('/')
    self.model = controller_name.singularize.camelize
  end

  def selected_columns
    grid_view_preferences.order(:sequence)
                         .to_h { |preference| [preference.label.presence || preference.name, preference.key] }
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
end
