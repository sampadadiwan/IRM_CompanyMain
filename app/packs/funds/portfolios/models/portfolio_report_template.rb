class PortfolioReportTemplate < ApplicationRecord
  belongs_to :portfolio_report
  belongs_to :style_document, class_name: "Document", optional: true

  # Style files are uploaded directly to the template (not the parent report).
  # We delegate folder/entity helpers so Document#setup_folder works without a
  # separate document_folder_id column on this model.
  has_many :documents, as: :owner, dependent: :destroy
  delegate :document_folder, :document_folder_id, :entity_id, :entity, to: :portfolio_report

  OUTPUT_FORMATS       = %w[word ppt].freeze
  AUTO_FREQUENCIES     = %w[monthly quarterly].freeze

  validates :name,          presence: true
  validates :output_format, inclusion: { in: OUTPUT_FORMATS }

  def to_s
    name
  end

  # Returns the PPT service class to use when output_format == "ppt".
  # Set branding["ppt_theme"] = "pastel" to use the pastel variant.
  def ppt_service_class
    if (branding || {}).fetch("ppt_theme", "default") == "pastel"
      PortfolioReportPastelPptService
    else
      PortfolioReportPptService
    end
  end

  # Returns section ids in configured order as integers (section_order is persisted as strings).
  def ordered_section_ids
    (section_order.presence || portfolio_report.portfolio_report_sections.pluck(:id)).map(&:to_i)
  end

  # Returns the kpi_layout config with symbolized keys and defaults applied.
  def kpi_config
    cfg = (kpi_layout || {}).with_indifferent_access
    cfg.reverse_merge(
      categories: [], # empty = all categories for this portco
      tags: ["Actual"],
      n_periods: 6,
      side_by_side: false
    )
  end
end
