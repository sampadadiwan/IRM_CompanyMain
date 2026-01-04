class AssistantTask < ApplicationRecord
  TYPES = %w[FundAssistant SpecificFundAssistant PortfolioCompanyAssistant PortfolioAssistant CapitalCommitmentAssistant].sort.freeze

  belongs_to :user
  belongs_to :entity

  validates :assistant_type, presence: true, inclusion: { in: TYPES }, length: { maximum: 50 }
  validates :period, presence: true, inclusion: { in: %w[Week Month Quarter Year] }, length: { maximum: 10 }
  validates :instructions, presence: true

  def tag_list=(tags)
    self[:tag_list] = tags.is_a?(Array) ? tags.join(", ") : tags
  end

  def tags
    tag_list&.split(",")&.map(&:strip) || []
  end

  def metadata
    @metadata ||= JSON.parse(assistant_metadata || "{}").with_indifferent_access
  rescue JSON::ParserError
    {}.with_indifferent_access
  end

  def owner_type
    {
      'PortfolioCompanyAssistant' => 'Investor',
      'CapitalCommitmentAssistant' => 'CapitalCommitment',
      'SpecificFundAssistant' => 'Fund'
    }[assistant_type]
  end

  def owner_id
    {
      'PortfolioCompanyAssistant' => metadata[:portfolio_company_id],
      'CapitalCommitmentAssistant' => metadata[:capital_commitment_id],
      'SpecificFundAssistant' => metadata[:fund_id]
    }[assistant_type]
  end
end
