class KanbanCardsController < ApplicationController
  before_action :set_kanban_card, only: %w[show edit update destroy move_kanban_card update_sequence]
  skip_before_action :verify_authenticity_token, only: %i[move_kanban_card update_sequence]

  def index
    @q = KanbanCard.ransack(params[:q])
    @kanban_cards = policy_scope(@q.result).includes(:kanban_board)
    @kanban_cards = @kanban_cards.where(kanban_board_id: params[:kanban_board_id]) if params[:kanban_board_id].present?
    @filtered_results = params[:query].present?
    kanban_board = KanbanBoard.find(params["board_id"])
    render turbo_stream: [
      turbo_stream.replace("board_#{kanban_board.id}", partial: "/boards/kanban", locals: { kanban_cards: @kanban_cards, kanban_board:, filtered_results: @filtered_results })
    ]
  end

  def new
    @kanban_card = KanbanCard.new(kanban_card_params)
    authorize @kanban_card

    @frame = params[:turbo_frame] || "board#{@kanban_card.kanban_board_id}_new_kanban_card"
    render turbo_stream: [
      turbo_stream.append(@frame, partial: "kanban_cards/form", locals: { kanban_card: @kanban_card, turbo_tag: @frame })
    ]
  end

  def create
    @kanban_card = KanbanCard.create!(kanban_card_params)
    kanban_board = @kanban_card.kanban_board
    authorize @kanban_card
    authorize kanban_board

    @frame = params[:turbo_frame] || params[:kanban_card][:turbo_frame] || "board#{@kanban_card.kanban_board_id}_new_kanban_card"
    respond_to do |format|
      if @kanban_card.persisted?
        format.html { redirect_to kanban_board_url(kanban_board), notice: "Card is successfully created." }
        format.json { render :show, status: :created }
        format.turbo_stream do
          UserAlert.new(user_id: current_user.id, message: "Card is successfully created.", level: "success").broadcast
          render :create, locals: { frame: @frame }
        end
      else
        @alert = "Card could not be created!"
        format.html do
          render :new, status: :unprocessable_entity
        end
        format.json { render json: @kanban_card.errors, status: :unprocessable_entity }
        @alert += " #{@kanban_card.errors.full_messages.join(', ')}"
        format.turbo_stream { render :create_failure, alert: @alert }
      end
    end
  end

  def show
    if params[:turbo]
      frame = params[:turbo_frame] || "card_offcanvas_turbo_frame"
      render turbo_stream: [
        turbo_stream.replace(frame, partial: "kanban_cards/offcanvas_show", locals: { kanban_card: @kanban_card, update_allowed: policy(@kanban_card).update?, turbo_tag: frame })
      ]
    end
  end

  def edit
    @kanban_column = @kanban_card&.kanban_column
    respond_to do |format|
      format.turbo_stream do
        frame = params[:turbo_frame] || "card_offcanvas_turbo_frame"
        render turbo_stream: [
          turbo_stream.replace(frame, partial: "kanban_cards/offcanvas_form", locals: { kanban_card: @kanban_card, update_allowed: policy(@kanban_card).update?, turbo_tag: frame })
        ]
      end
    end
  end

  def update
    @frame = params[:turbo_frame] || params["kanban_card"]["turbo_frame"] || "card_offcanvas_turbo_frame"
    @current_user = current_user

    respond_to do |format|
      format.turbo_stream { render :update }
      if @kanban_card.update(kanban_card_params)
        format.html { redirect_to @kanban_card, notice: 'Card was successfully updated.' }
        format.json { render :show, status: :ok, location: @kanban_card }
      else
        format.html { render :edit }
        format.json { render json: @kanban_card.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @kanban_card.destroy

    respond_to do |format|
      format.html { redirect_to @kanban_card.kanban_board, notice: "Card was successfully deleted." }
      format.json { head :no_content }
    end
  end

  def move_kanban_card
    result = MoveKanbanCard.call(params:, kanban_card: @kanban_card)
    if result.success?
      render json: {
        message: "Card has been successfully moved"
      }, status: :ok
    else
      render json: { errors: result["errors"] }, status: :unprocessable_entity
    end
  end

  def update_sequence
    result = UpdateCardSequence.call(params:, kanban_card: @kanban_card)
    if result.success?
      render json: {
        message: "Card has been successfully moved"
      }, status: :ok
    else
      render json: { errors: result["errors"] }, status: :unprocessable_entity
    end
  end

  def search
    @entity = current_user.entity
    @q = DealInvestor.ransack(params[:q])
    @filtered_results = false
    @searched_kanban_cards = nil
    if params[:query].present?
      @filtered_results = true
      kanban_card_ids = KanbanCardIndex.filter(term: { entity_id: @entity.id })
                                       .query(query_string: { fields: KanbanCardIndex::SEARCH_FIELDS,
                                                              query: "*#{params[:query]}*", default_operator: 'and' }).objects.compact.pluck(:id)
      @searched_kanban_cards = KanbanCard.where(id: kanban_card_ids)
    end
    kanban_board = KanbanBoard.find(params[:kanban_board])
    render turbo_stream: [
      turbo_stream.replace("board_#{kanban_board.id}", partial: "/boards/kanban", locals: { kanban_board:, filtered_results: @filtered_results, kanban_cards: @searched_kanban_cards })
    ]
  end

  private

  def set_kanban_card
    @kanban_card = KanbanCard.find(params[:id])
    authorize @kanban_card
  end

  # Only allow a list of trusted parameters through.
  def kanban_card_params
    params.require(:kanban_card).permit(:entity_id, :kanban_board_id, :kanban_column_id, :data_source_id, :data_source_type, :title, :info_field, :notes, :tags)
  end
end
