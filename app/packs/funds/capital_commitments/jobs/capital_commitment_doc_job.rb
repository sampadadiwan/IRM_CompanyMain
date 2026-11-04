class CapitalCommitmentDocJob < DocGenJob
  # M9 — a picked template_id is resolved only inside this fund's template set: the fund's Commitment
  # Templates, plus (for one commitment) that commitment's own template overrides. Another firm's or
  # another fund's document id finds nothing, so the run stops with "No templates found" and never
  # renders that template or deletes this commitment's same-named generated documents.
  # Tests M9-X1, M9-H1 — features/security/security_review_2026_10_funds.feature
  def templates(model = nil)
    if @template_id.present?
      # The commitment being generated for (or the one the job was started for, during the input check)
      commitment = model || (@capital_commitment_id.present? && models.first)
      # The fund's own Commitment Template with this id (M9-H1)
      allowed = @fund.documents.templates.where(owner_tag: "Commitment Template", id: @template_id).to_a
      # ... or this commitment's own override template with this id, as offered on the commitment page (M9-H2)
      allowed += commitment.documents.templates.where(id: @template_id).to_a if commitment
      allowed
    elsif model.present?
      model.templates("Commitment Template", id: @template_id)
    else
      @fund.documents.templates.where(owner_tag: "Commitment Template")
    end
  end

  def models
    if @capital_commitment_id.present?
      # M9 — the commitment is looked up inside the job's fund, so the fund's templates are the ones that apply
      @fund.capital_commitments.where(id: @capital_commitment_id)
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
