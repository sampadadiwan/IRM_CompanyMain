class CapitalDistributionPaymentDocJob < DocGenJob
  # Returns the Distribution Template using the id , or but name using the model;s commitment or the fund
  def templates(model = nil)
    if @template_id.present?
      [Document.find(@template_id)]
    elsif model.present?
      model.capital_commitment.templates("Distribution Template")
    else
      @fund.documents.templates.where(owner_tag: "Distribution Template")
    end
  end

  # Returns the models to generate documents for
  # If @capital_distribution_payment_id is present, it returns that specific payment
  # Otherwise, it returns all payments for the capital distribution
  def models
    if @capital_distribution_payment_id.present?
      [CapitalDistributionPayment.find(@capital_distribution_payment_id)]
    else
      @capital_distribution.capital_distribution_payments
    end
  end

  # Validates that the capital distribution payment is present and that the investor KYC is verified
  def validate(capital_distribution_payment)
    return false, "No Capital Distribution Payment found" if capital_distribution_payment.blank?
    return false, "Investor Kyc not verified" if capital_distribution_payment.investor_kyc.blank? || !capital_distribution_payment.investor_kyc.verified

    [true, ""]
  end

  def generator
    CapitalDistributionPaymentDocGenerator
  end

  def cleanup_previous_docs(model, template)
    # Delete any existing signed documents
    model.documents.not_templates.where(name: template.name).find_each(&:destroy)
  end

  def generate_doc_name(model, template, _start_date, _end_date)
    "#{template.name} - #{model.investor_name}"
  end

  # This is idempotent, we should be able to call it multiple times for the same CapitalDistributionPayment
  def perform(capital_distribution_id, capital_distribution_payment_id, user_id, template_id: nil)
    @capital_distribution_id = capital_distribution_id
    @capital_distribution = CapitalDistribution.find(capital_distribution_id)
    @fund = @capital_distribution.fund
    @capital_distribution_payment_id = capital_distribution_payment_id

    @start_date = Time.zone.now
    @end_date = Time.zone.now
    @user_id = user_id
    @template_id = template_id

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id) if valid_inputs
    end

    @error_msg
  end
end
