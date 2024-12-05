class CapitalCommitmentDocJob < DocGenJob
  def templates(model = nil)
    if @template_id.present?
      [Document.find(@template_id)]
    elsif model.present?
      model.templates("Commitment Template", @template_name)
    else
      @fund.documents.templates.where(owner_tag: "Commitment Template")
    end
  end

  def models
    if @capital_commitment_id.present?
      [CapitalCommitment.find(@capital_commitment_id)]
    else
      @fund.capital_commitments
    end
  end

  def validate(capital_commitment)
    return false, "No Capital Commitment found" if capital_commitment.blank?
    return false, "No Investor KYC found" if capital_commitment.investor_kyc.blank?

    [capital_commitment.investor_kyc.verified, "#{capital_commitment.investor_kyc.full_name} is not verified"]
  end

  def generator
    CapitalCommitmentDocGenerator
  end

  def cleanup_previous_docs(model, template)
    # Delete any existing signed documents
    # Do not delete signed documents
    docs_to_destroy = model.documents.not_templates.where(name: template.name)
    # .where.not translates to != in SQL. NULL is treated differently from other values, so != queries never match columns that are set to NULL
    docs_to_destroy.where.not(owner_tag: %w[Signed signed]).or(docs_to_destroy.where(owner_tag: nil)).find_each(&:destroy)
  end

  def generate_doc_name(model, template, _start_date, _end_date)
    "#{template.name} - #{model}"
  end

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, capital_commitment_id, user_id = nil, template_id: nil)
    @start_date = Time.zone.now
    @end_date = Time.zone.now

    @fund_id = fund_id
    @fund = Fund.find(fund_id)

    @capital_commitment_id = capital_commitment_id

    @user_id = user_id
    @template_id = template_id

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id) if valid_inputs
    end
  end
end
