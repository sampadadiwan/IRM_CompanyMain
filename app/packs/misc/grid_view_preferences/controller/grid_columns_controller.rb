# ③④ The columns side panel on a table: loads the panel into its frame and saves the whole list at once.
# Configure Grids (GridViewPreferencesController) stays as it is.
# openspec/changes/grid-columns-inline-settings — design D3; lld.md › Controllers, Params and Responses
class GridColumnsController < ApplicationController
  before_action :load_context

  # GET /grid_columns/settings?context=<signed token> — the panel body, inside the "grid_columns" frame
  def settings
    @rows = helpers.grid_columns_rows(@context)
    render layout: false
  end

  # PATCH /grid_columns/save — context, rows (JSON), reset, embedded; nothing else is read (X8)
  def save
    result = GridColumnsSave.call(user: current_user, context: @context, rows: save_params[:rows], reset: save_params[:reset])
    if result.success?
      # ⑥ The saved marker: the panel controller closes the panel and reloads the table's frame
      render partial: "grid_columns/saved", locals: { label: "#{helpers.grid_columns_title(@context)} saved" }, layout: false
    else
      # X4, X6 — the panel again, with the reasons and the list as it was submitted
      @errors = result.errors
      @rows = helpers.grid_columns_rows_from_submission(@context, save_params[:rows])
      @reset = ActiveModel::Type::Boolean.new.cast(save_params[:reset])
      # D19 — refused on the full Configure Grids page: the editor again, embedded
      @embedded = save_params[:embedded] == "1"
      render :settings, layout: false, status: :unprocessable_content
    end
  end

  private

  # X5, X9, X3 — the signed context (404 when altered, expired, an unknown model or a report outside the user's
  # scope), then the policy on an unsaved column for the owner: X1 company admin of the firm, X2 not acting as
  # an investor, X7 may edit the report
  def load_context
    @context = GridColumnsContext.from_token(save_params[:context], user: current_user)
    authorize GridViewPreference.new(owner: @context.owner, entity_id: @context.entity.id), :inline_columns?
  end

  def save_params
    params.permit(:context, :rows, :reset, :embedded)
  end
end
