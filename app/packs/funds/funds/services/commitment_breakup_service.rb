class CommitmentBreakupService
  def initialize(fund)
    @fund = fund
  end

  def call
    original_cents = @fund.capital_commitments.sum(:orig_committed_amount_cents)
    top_up_cents = @fund.commitment_adjustments.top_up.sum(:amount_cents)
    fx_cents = @fund.commitment_adjustments.exchange_rate.sum(:amount_cents)
    total_cents = @fund.capital_commitments.sum(:committed_amount_cents)

    # We might have other adjustments (like Transfer, which should net to 0 for the fund)
    # But to be safe and ensure the waterfall adds up, we can calculate 'Other'
    other_cents = total_cents - (original_cents + top_up_cents + fx_cents)

    divisor = @fund.currency == 'INR' ? 1_000_000_000.0 : 100_000_000.0

    data = []
    data << {
      name: "Original Commitment<br/>(#{format_amount(original_cents)})",
      y: (original_cents / divisor).to_f,
      label: format_amount(original_cents),
      color: '#5D87FF' # Blue
    }
    data << {
      name: "Top Up Adjustments<br/>(#{format_amount(top_up_cents)})",
      y: (top_up_cents / divisor).to_f,
      label: format_amount(top_up_cents),
      color: '#763EBD' # Purple
    }
    data << {
      name: "FX Adjustments<br/>(#{format_amount(fx_cents)})",
      y: (fx_cents / divisor).to_f,
      label: format_amount(fx_cents),
      color: '#FFAE1F' # Orange
    }

    if other_cents != 0
      data << {
        name: "Other Adjustments<br/>(#{format_amount(other_cents)})",
        y: (other_cents / divisor).to_f,
        label: format_amount(other_cents),
        color: '#FA896B' # Coral
      }
    end

    data << {
      name: "Total Adjusted Commitment<br/>(#{format_amount(total_cents)})",
      isSum: true,
      label: format_amount(total_cents),
      color: '#5D87FF' # Blue
    }

    data
  end

  private

  def format_amount(cents)
    amount = cents / 100.0
    if @fund.currency == 'INR'
      "#{(amount / 10_000_000.0).round(2)} Cr"
    else
      "#{(amount / 1_000_000.0).round(2)} M"
    end
  end
end
