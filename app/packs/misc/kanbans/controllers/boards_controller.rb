# BoardsController handles the management of Kanban boards within the application.
#
# Overview:
# - A Board belongs to an owner, which is a polymorphic association For ex - It can be owned by a deal.
# - A Board can also belong to itself.
# - A Board has many KanbanColumns.
# - Each KanbanColumn has many KanbanCards.
# - KanbanCards can have a data_source, which can also be itself.
# - Boards can be created either directly via the view (Plain Boards) or through a concern when the owner is another module.
# - Two concerns, KanbanBoardManager and KanbanCardManager, manage the creation and updating of boards and cards respectively.
# - Board also syncs very well among multiple users if present on same board via EventsChannel.
class BoardsController < ApplicationController
  before_action :set_kanban_board, only: %w[show edit update destroy]
  skip_after_action :verify_authorized, only: %w[owner_ids]

  def show
    data_source = if @kanban_board.kanban_cards.present?
                    @kanban_board.kanban_cards.first.data_source_type
                  else
                    "KanbanCard"
                  end

    records = Pundit.policy_scope(current_user, data_source.constantize)
    @q = records.ransack(params[:q])
    @kanban_cards = KanbanCard.where(data_source_type: data_source, data_source_id: @q.result.pluck(:id))
  end

  def index
    @kanban_boards = policy_scope(KanbanBoard)
    @kanban_boards = @kanban_boards.where(owner_type: params[:owner_type]) if params[:owner_type].present?
    @bread_crumbs = { Boards: boards_path }

    # @boards = @boards.where("boards.archived=?", false) if params[:include_archived].blank?
  end

  def new
    @kanban_board = KanbanBoard.new(kanban_board_params)
    @kanban_board.entity_id = current_user.entity_id
    authorize @kanban_board

    render :new
  end

  def owner_ids
    if params[:owner_type] == "Blank"
      @owner_ids = []
      return
    end
    @owner_type = params[:owner_type].constantize
    name_attr = KanbanBoard::OWNER_TYPES[@owner_type.to_s.to_sym]
    @owner_ids = @owner_type.where(entity_id: current_user.entity_id).pluck(name_attr.to_sym, :id)
    @owner_ids || []
  end

  def create
    @kanban_board = KanbanBoard.create!(kanban_board_params)
    @kanban_board.update(owner_type: "KanbanBoard", owner_id: @kanban_board.id)
    authorize @kanban_board
    @kanban_board.create_columns

    respond_to do |format|
      if @kanban_board.persisted?
        format.html { redirect_to board_url(@kanban_board), notice: "Board was successfully created." }
        format.json { render :show, status: :created, location: @kanban_board }
        # format.turbo_stream { render :create }
      else
        @alert = "Board could not be created!"
        format.html do
          render :new, status: :unprocessable_entity
        end
        format.json { render json: @kanban_board.errors, status: :unprocessable_entity }
        @alert += " #{@kanban_board.errors.full_messages.join(', ')}"
        format.turbo_stream { render :create_failure, alert: @alert }
      end
    end
  end

  def edit
    if params[:turbo]
      frame = params[:turbo_frame_id] || "board#{@kanban_board.id}_edit"
      render turbo_stream: [
        turbo_stream.replace(frame, partial: "boards/form", locals: { kanban_board: @kanban_board, turbo_frame_id: frame, turbo: true })
      ]
    end
  end

  def update
    respond_to do |format|
      if @kanban_board.update(kanban_board_params)
        format.html { redirect_to @kanban_board, notice: 'Board was successfully updated.' }
        format.json { render :show, status: :ok, location: @kanban_board }
      else
        format.html { render :edit }
        format.json { render json: @kanban_board.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @kanban_board.destroy

    respond_to do |format|
      format.html { redirect_to boards_url, notice: "Kanban Board was successfully deleted." }
      format.json { head :no_content }
    end
  end

  def archived_kanban_columns
    @kanban_board = KanbanBoard.find(params[:kanban_board_id])
    authorize @kanban_board
    @archived_columns = @kanban_board.kanban_columns.only_deleted
    if params[:turbo]
      render turbo_stream: [
        turbo_stream.replace("archived_columns_#{params[:kanban_board_id]}", partial: "kanban_columns/archived", locals: { kanban_columns: @archived_columns })
      ]
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_kanban_board
    @kanban_board = KanbanBoard.find(params[:id])
    authorize @kanban_board
    @bread_crumbs = { Boards: boards_path, "#{@kanban_board.name}": board_path(@kanban_board) }
    @owner_type = "KanbanBoard"
    @owner_id = @kanban_board.id
    if @kanban_board.owner_type != @kanban_board.class.to_s
      owner_path = polymorphic_path(@kanban_board.owner_type.to_s.pluralize.downcase)
      @bread_crumbs = { "#{@kanban_board.owner_type&.to_s&.pluralize}": owner_path, "#{@kanban_board.name}": board_path(@kanban_board) } if owner_path.present?
    end
  end

  # Only allow a list of trusted parameters through.
  def kanban_board_params
    params.require(:kanban_board).permit(:entity_id, :owner_id, :owner_type, :name)
  end
end
