class DealMessagesController < ApplicationController
  before_action :set_deal_message, only: %w[show update destroy edit mark_as_task task_done]
  after_action :verify_policy_scoped, only: []

  # GET /deal_messages or /deal_messages.json
  def index
    if params[:deal_investor_id]
      @deal_investor = DealInvestor.find(params[:deal_investor_id])
      # Ensure the user has access to the deal investor
      authorize @deal_investor, :show?
      # Mark messages as read
      @deal_investor.messages_viewed(current_user)
      # Return the messages
      @deal_messages = @deal_investor.deal_messages.with_all_rich_text.includes(:user)
    elsif params[:tasks].present?
      @deal_messages = if params[:show_all].present?
                         DealMessage.where(entity_id: current_user.entity_id).tasks
                       else
                         DealMessage.where(entity_id: current_user.entity_id).tasks_not_done
                       end

      @deal_messages = @deal_messages.with_all_rich_text.includes(:user, :deal_investor)
    else
      @deal_messages = DealMessage.none
    end

    @deal_messages = @deal_messages.where(investor_id: params[:investor_id]) if params[:investor_id].present?
    @deal_messages = @deal_messages.where(user_id: params[:user_id]) if params[:user_id].present?
  end

  # GET /deal_messages/1 or /deal_messages/1.json
  def show
    authorize @deal_message
  end

  # GET /deal_messages/new
  def new
    @deal_message = DealMessage.new(deal_message_params)
    @deal_message.user_id = current_user.id
    @deal_message.entity_id = @deal_message.deal_investor.entity_id
    authorize @deal_message
  end

  # GET /deal_messages/1/edit
  def edit
    authorize @deal_message
  end

  # POST /deal_messages or /deal_messages.json
  def create
    @deal_message = DealMessage.new(deal_message_params)
    @deal_message.user_id = current_user.id
    @deal_message.entity_id = @deal_message.deal_investor.entity_id
    authorize @deal_message

    respond_to do |format|
      if @deal_message.save
        format.turbo_stream { render :create }
        format.html { redirect_to deal_message_url(@deal_message), notice: "Deal message was successfully created." }
        format.json { render :show, status: :created, location: @deal_message }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @deal_message.errors, status: :unprocessable_entity }
      end
    end
  end

  def mark_as_task
    authorize @deal_message
    @deal_message.is_task = !@deal_message.is_task

    respond_to do |format|
      if @deal_message.save
        format.turbo_stream do
          render turbo_stream: [
            if @deal_message.is_task
              turbo_stream.append('deal_message_tasks', partial: "deal_messages/deal_message",
                                                        locals: { deal_message: @deal_message })
            else
              turbo_stream.remove(@deal_message)
            end
          ]
        end
      end
    end
  end

  def task_done
    authorize @deal_message
    @deal_message.task_done = !@deal_message.task_done

    respond_to do |format|
      if @deal_message.save
        format.turbo_stream do
          render turbo_stream: [
            # if @deal_message.task_done
            #   turbo_stream.remove(@deal_message)
            # else
            #   turbo_stream.replace(@deal_message)
            # end
            turbo_stream.replace(@deal_message)
          ]
        end
      end
    end
  end

  # PATCH/PUT /deal_messages/1 or /deal_messages/1.json
  def update
    authorize @deal_message

    respond_to do |format|
      if @deal_message.update(deal_message_params)
        format.html { redirect_to deal_message_url(@deal_message), notice: "Deal message was successfully updated." }
        format.json { render :show, status: :ok, location: @deal_message }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @deal_message.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /deal_messages/1 or /deal_messages/1.json
  def destroy
    authorize @deal_message
    @deal_message.destroy

    respond_to do |format|
      format.html { redirect_to deal_messages_url, notice: "Deal message was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_deal_message
    @deal_message = DealMessage.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def deal_message_params
    params.require(:deal_message).permit(:user_id, :content, :deal_investor_id, :task_done,
                                         :is_task, :not_msg)
  end
end
