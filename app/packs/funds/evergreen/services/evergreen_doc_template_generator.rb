# Renders a fund's (or folio's) "Contract Note Template" / "Redemption Advice Template" (Word, Sablon)
# for one dealing fill and saves the PDF on the folio as an unapproved generated document — the same
# pipeline as CapitalDistributionPaymentDocGenerator. open-ended-funds § Dealing-date documents
class EvergreenDocTemplateGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_reader :generated_document

  def initialize(fill, template, user_id)
    @fill = fill
    folio = fill.dealing_order.capital_commitment
    kind = EvergreenDealingDocuments.kind(fill)
    template.file.download do |tempfile|
      create_working_dir(fill)
      sablon = Sablon.template(File.expand_path(tempfile.path))
      # upload() reads "#{generated_file_name(folio)}.pdf", so render under the folio's name
      convert(sablon, context(fill, folio, kind), generated_file_name(folio), template_name: template.name, doc_template: template)
      # Saved on the folio; DocumentGeneratorBase#upload marks it "Generated" (hidden from investors until approved)
      # The fill id keeps two orders of one folio on one date from replacing each other's document
      upload(template, folio, nil, nil, nil, "#{template.name} - #{fill.dealing_date.date.iso8601} - #{folio.folio_id} - #{fill.id}",
             user_id:, as_of: fill.dealing_date.date)
    ensure
      cleanup
    end
  end

  private

  # Template fields: the records (decorated, like other templates) plus ready-formatted values under
  # `evergreen` — e.g. {{evergreen.units_allotted}}, {{evergreen.nav_per_unit}}, {{evergreen.net_paid}}
  def context(fill, folio, kind)
    # Fixed field names, whatever the fund's labels say (EvergreenDocumentGenerator#fields)
    values = EvergreenDocumentGenerator.new(fill, kind).fields
    {
      date: I18n.l(Time.zone.today, format: :email, locale: :en),
      entity: fill.entity,
      fund: TemplateDecorator.decorate(fill.fund),
      capital_commitment: TemplateDecorator.decorate(folio),
      investor: TemplateDecorator.decorate(fill.dealing_order.investor),
      investor_kyc: TemplateDecorator.decorate(folio.investor_kyc),
      dealing_order: TemplateDecorator.decorate(fill.dealing_order),
      dealing_fill: TemplateDecorator.decorate(fill),
      evergreen: values
    }
  end
end
