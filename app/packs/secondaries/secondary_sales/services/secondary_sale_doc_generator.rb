class SecondarySaleDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  def initialize(secondary_sale, template, _start_date, _end_date, _user_id)
    create_working_dir(secondary_sale)
    template_path ||= download_template(template)
    generate(secondary_sale, template, template_path)
    generated_document_name = "#{template.name} #{secondary_sale.name}"
    upload(template, secondary_sale, nil, nil, nil, generated_document_name, user_id: user_id)
  ensure
    cleanup
  end

  private

  def working_dir_path(secondary_sale)
    "tmp/secondary_sale_spa_generator/#{rand(1_000_000)}/#{secondary_sale.id}"
  end

  def download_template(template)
    file = template.file.download
    file.path
  end

  # template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(secondary_sale, _template_document, template_path)
    template = Sablon.template(File.expand_path(template_path))

    context = {}
    context.store  :effective_date, Time.zone.today.strftime("%d %B %Y")
    context.store  :secondary_sale, TemplateDecorator.decorate(secondary_sale)
    context.store  :entity, secondary_sale.secondary_sale.entity

    context.store  :allocations, TemplateDecorator.decorate(secondary_sale.allocations)
    TemplateDecorator.decorate(context[:secondary_sale].custom_fields)

    current_date = Time.zone.now.strftime('%d/%m/%Y')
    context.store :current_date, current_date

    file_name = generated_file_name(secondary_sale)
    convert(template, context, file_name)
  end

  def pivot_for_investors
    rows = []
    secondary_sale.interests.includes(:investor).short_listed.group_by { |i| i.investor.investor_name }.each do |investor_name, interests|
      row = OpenStruct.new
      ids = interests.map(&:id)
      row.investor_name = investor_name
      row.buy_quantity = interests.sum(&:quantity)
      row.interest_count = interests.count
      row.completed = interests.count { |interest| interest.completed == true }
      row.incomplete = interests.count { |interest| interest.completed != true }
      row.loi_generated = Interest.joins(:documents).where("interests.id in (?) and documents.approved=? and (name LIKE ? OR name LIKE ?)", ids, true, "%Letter of intent%", "%LOI%").count

      # row.spa_generated = interests.joins(allocations: :documents).where("documents.approved=? and (name LIKE ? OR name LIKE ?)", true, "%Purchase Agreement%", "%SPA%").count

      row.spa_generated = Interest.joins(allocations: :documents).where("interests.id in (?) and documents.approved=? and (name LIKE ? OR name LIKE ?)", ids, true, "%Purchase Agreement%", "%SPA%").count

      rows << row
    end
    rows
  end

  def pivot_for_rms; end
end
