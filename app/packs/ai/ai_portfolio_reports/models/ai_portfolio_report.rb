class AiPortfolioReport < ApplicationRecord
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :analyst, class_name: "User"
  has_many :ai_report_sections, dependent: :destroy
  has_many :ai_chat_sessions, dependent: :destroy

  enum :status, {
    draft: 'draft',
    in_review: 'in_review',
    finalized: 'finalized'
  }

  # Set default status
  #
  #
  after_initialize do
    self.status = 'draft' if new_record? && status.nil?
  end

  after_create :create_default_sections

  SECTION_TYPES = [
    "Company Overview",
    "Key Products & Services",
    "Financial Snapshot",
    "Market Size & Target",
    "Recent Updates & Developments",
    "Custom Charts",
    "Founders & Shareholders",
    "Raise History, Valuations & Funding Trend",
    "SWOT Analysis",
    "Competition Analysis",
    "Key Risks",
    "Operational Red Flags",
    "Negative News",
    "AML/KYB Check",
    "Investment Ask"
  ].freeze

  # Sections that benefit from web search (current external information)
  WEB_SEARCH_DEFAULT_SECTIONS = [
    "Company Overview",
    "Key Products & Services",
    "Market Size & Target",
    "Recent Updates & Developments",
    "Founders & Shareholders",
    "Raise History, Valuations & Funding Trend",
    "SWOT Analysis",
    "Competition Analysis",
    "Key Risks",
    "Operational Red Flags",
    "Negative News"
  ].freeze

  private

  def create_default_sections
    SECTION_TYPES.each_with_index do |section_type, index|
      ai_report_sections.create!(
        section_type: section_type,
        order_index: index + 1,
        status: 'draft',
        web_search_enabled: false
      )
    end
  end
end
