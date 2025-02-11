class KanbanColumnsController < ApplicationController
  before_action :set_kanban_column, only: %w[show update update_sequence edit destroy delete_column]
  skip_before_action :verify_authenticity_token, only: %i[update_sequence update delete_column]

  def update_sequence
    result = UpdateSequence.wtf?(params:, kanban_column: @kanban_column)
    if result.success?
      render json: {
        message: "Column has been successfully moved"
      }, status: :ok
    else
      render json: { errors: result["errors"] }, status: :unprocessable_entity
    end
  end

  def new
    @kanban_column = KanbanColumn.new(kanban_column_params)
    @kanban_column.entity_id ||= current_user.entity_id
    authorize @kanban_column

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("new_kanban_column#{@kanban_column.kanban_board_id}", partial: "kanban_columns/form", locals: { kanban_column: @kanban_column })
        ]
      end
    end
  end

  def create
    @kanban_column = KanbanColumn.new(kanban_column_params)
    @kanban_board_id = @kanban_column.kanban_board_id
    @kanban_column.entity_id ||= current_user.entity_id

    authorize @kanban_column

    respond_to do |format|
      if @kanban_column.save
        UserAlert.new(user_id: current_user.id, message: "Column was successfully created!", level: "success").broadcast
        format.turbo_stream { render :create }

        format.html { redirect_to kanban_board_path(@kanban_column.kanban_board), notice: "Kanban column was successfully created." }
        format.json { render json: @kanban_column, status: :created }
      else
        @alert = "Column could not be created!"
        @alert += " #{@kanban_column.errors.full_messages.join(', ')}"
        format.turbo_stream { render :create_failure, alert: @alert }
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @kanban_column.errors, status: :unprocessable_entity }
      end
    end
  end

  def show; end

  def edit
    if params[:turbo]
      render turbo_stream: [
        turbo_stream.replace("kanban_column_edit_#{@kanban_column.id}", partial: "kanban_columns/form", locals: { kanban_column: @kanban_column })
      ]
    end
  end

  def update
    if @kanban_column.update(kanban_column_params)
      respond_to do |format|
        UserAlert.new(user_id: current_user.id, message: "Column was successfully updated!", level: "success").broadcast
        format.turbo_stream { render :create }
        format.json { render json: @kanban_column, status: :ok }
      end
    else
      respond_to do |format|
        format.json { render json: @kanban_column.errors, status: :unprocessable_entity }
      end
    end
  end

  def delete_column
    result = ArchiveKanbanColumn.wtf?(params:, kanban_column: @kanban_column)
    if result.success?
      UserAlert.new(user_id: current_user.id, message: "Column #{@kanban_column.name} Deleted", level: "success").broadcast
    else
      errors = "Column could not be deleted! #{result['errors']}"
      UserAlert.new(user_id: current_user.id, message: errors, level: "error").broadcast
      render json: { errors: }, status: :unprocessable_entity
    end
  end

  def restore_column
    @kanban_column = KanbanColumn.only_deleted.find(params[:id])
    authorize @kanban_column
    result = RestoreColumn.wtf?(params:, kanban_column: @kanban_column)
    if result.success?
      UserAlert.new(user_id: current_user.id, message: "Column was successfully restored!", level: "success").broadcast
    else
      errors = "Column could not be restored! #{result['errors']}"
      UserAlert.new(user_id: current_user.id, message: errors, level: "error").broadcast
      render json: { errors: }, status: :unprocessable_entity
    end
  end

  private

  def set_kanban_column
    @kanban_column = KanbanColumn.find(params[:id])
    authorize @kanban_column
  end

  def kanban_column_params
    params.require(:kanban_column).permit(:entity_id, :kanban_board_id, :name, :sequence)
  end
end
