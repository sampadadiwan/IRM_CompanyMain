# Rows of a statement's layout: headings, accounts, subtotals, net result and opening / closing
# capital. Reordered with the Up / Down buttons.
# Worked examples H2, H3, H24 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementLayoutRowsController < ApplicationController
  include FinancialStatementFundContext

  before_action :set_row, only: %i[edit update destroy]
  after_action :verify_authorized

  def new
    definition = policy_scope(FinancialStatementDefinition).find(params[:definition_id])
    @fund = definition.fund
    # The row type picked on the Layout tab ("+ Heading", "+ Account", "+ Subtotal")
    @row = definition.layout_rows.new(fund: @fund, entity_id: @fund.entity_id, row_type: params[:row_type].presence || "account")
    authorize @row
    fund_breadcrumbs("Add row to #{definition.name}")
  end

  # New rows go to the end; the user moves them with Up / Down
  def create
    definition = policy_scope(FinancialStatementDefinition).find(params.dig(:financial_statement_layout_row, :financial_statement_definition_id))
    @fund = definition.fund
    # Appended at the end of the statement
    position = (definition.layout_rows.maximum(:position) || 0) + 1
    @row = definition.layout_rows.new(row_params.merge(fund: @fund, entity_id: @fund.entity_id, position:))
    authorize @row
    if @row.save
      redirect_to layout_path(definition), notice: "#{@row.display_label} added to #{definition.name}."
    else
      fund_breadcrumbs("Add row to #{definition.name}")
      render :new, status: :unprocessable_content
    end
  end

  def edit
    fund_breadcrumbs("Edit row")
  end

  def update
    if @row.update(row_params)
      redirect_to layout_path(@row.definition), notice: "#{@row.display_label} saved."
    else
      fund_breadcrumbs("Edit row")
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @row.destroy!
    redirect_to layout_path(@row.definition), notice: "#{@row.display_label} removed from #{@row.definition.name}."
  end

  # POST /financial_statement_layout_rows/sort?id=&direction=up|down — H3: swaps with its neighbour
  def sort
    row = policy_scope(FinancialStatementLayoutRow).find(params[:id])
    authorize row, :update?
    rows = row.definition.layout_rows.to_a
    index = rows.index(row)
    # H3: swap with the row above (up) or below (down); none at the ends
    neighbour = if params[:direction] == "up"
                  index.positive? ? rows[index - 1] : nil
                else
                  rows[index + 1]
                end
    if neighbour
      FinancialStatementLayoutRow.transaction do
        # Renumber first so equal positions can't make a swap a no-op
        rows.each_with_index { |r, i| r.update_column(:position, i + 1) unless r.position == i + 1 }
        a = row.reload.position
        b = neighbour.reload.position
        row.update_column(:position, b)
        neighbour.update_column(:position, a)
      end
    end
    redirect_to layout_path(row.definition)
  end

  private

  def set_row
    @row = policy_scope(FinancialStatementLayoutRow).find(params[:id])
    @fund = @row.fund
    authorize @row
  end

  def layout_path(definition)
    financial_statement_definitions_path(fund_id: definition.fund_id, definition_id: definition.id)
  end

  def row_params
    attrs = params.expect(financial_statement_layout_row: [:row_type, :label, :financial_statement_account_id, { subtotal_of: [] }])
    # Checkbox lists send a blank first value; store integer row ids
    attrs[:subtotal_of] = Array(attrs[:subtotal_of]).compact_blank.map(&:to_i) if attrs.key?(:subtotal_of)
    # Only account rows point at an account
    attrs[:financial_statement_account_id] = nil unless attrs[:row_type] == "account"
    attrs
  end
end
