# Generate statements (SOAs) for one evergreen folio or every folio of the fund: validates the form and
# queues the existing CapitalCommitmentSoaJob, which renders the fund's / folio's SOA template with the
# evergreen figures (EvergreenStatement#template_context). Nothing here renders a document itself.
# Worked examples H4, H5, E10, E11, E12, X6, X7, X8, X9 — openspec/changes/evergreen-folio-soa/design.md#worked-examples
module Evergreen
  class StatementsController < BaseController
    before_action :require_evergreen!

    TEMPLATE_TAGS = ["SOA Template", "Investor Statement Template"].freeze

    # The templates the form offers: a folio's own (overriding the fund's, E11) or the fund's
    def self.templates_for(fund, folio = nil)
      folio ? folio.templates(TEMPLATE_TAGS) : fund.documents.templates.where(owner_tag: TEMPLATE_TAGS)
    end

    def create
      @folio = @fund.capital_commitments.find(params[:capital_commitment_id]) if params[:capital_commitment_id].present?
      # X8: one folio needs the existing SOA right (approved KYC + update, X10); the whole fund the
      # allocation screen's right, which also generates investor statements today
      @folio ? authorize(@folio, :generate_soa?) : authorize(@fund, :allocate?)
      back = @folio ? evergreen_folio_path(@fund, @folio) : evergreen_investors_path(@fund)

      start_date = parse_date(params[:start_date])
      end_date = parse_date(params[:end_date])
      # X9: only this fund's (or folio's) templates
      template = Array(self.class.templates_for(@fund, @folio)).find { |t| t.id == params[:template_id].to_i }
      error = if start_date.nil? || end_date.nil? then "Enter a start date and an end date"
              # X6 (E10: start = end is a one-day period)
              elsif start_date > end_date then "Start date must be on or before end date"
              elsif template.nil? then "Template not found"
              end
      return redirect_to(back, alert: error) if error

      # H4 one folio / H5 all folios (nil). The job skips folios without a verified KYC and periods
      # already approved (E16), and replaces unapproved ones (E12)
      # The job looks the id up among the FUND's templates and then swaps in a folio's own template of the
      # same name (CapitalCommitment#templates), so a folio override is passed as its fund template (E11)
      fund_template_id = @fund.documents.templates.where(owner_tag: TEMPLATE_TAGS, name: template.name).pick(:id) || template.id
      CapitalCommitmentSoaJob.perform_later(@fund.id, @folio&.id, start_date.iso8601, end_date.iso8601, current_user.id, template_id: fund_template_id)
      redirect_to back, notice: "#{@folio ? 'Statement is' : 'Statements are'} being generated — you'll be notified when done."
    end

    private

    def parse_date(value)
      Date.local_parse(value.to_s) if value.present?
    rescue ArgumentError # Date::Error is an ArgumentError
      nil
    end
  end
end
