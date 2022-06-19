class MessagesController < ApplicationController
  before_action :set_message, only: %w[show update destroy edit mark_as_task task_done]
  after_action :verify_policy_scoped, only: []

  # GET /messages or /messages.json
  def index
    if params[:owner_id].present? && params[:owner_type].present?
      @owner = Message.new(owner_id: params[:owner_id], owner_type: params[:owner_type]).owner
      # Ensure the user has access to the deal investor
      authorize @owner, :show?
      # Mark messages as read
      # @owner.messages_viewed(current_user)
      # Return the messages
      @messages = @owner.messages
    else
      @messages = Message.none
    end

    @messages = @messages.with_all_rich_text.includes(:user)
    @messages = @messages.where(investor_id: params[:investor_id]) if params[:investor_id].present?
    @messages = @messages.where(user_id: params[:user_id]) if params[:user_id].present?
  end

  # GET /messages/1 or /messages/1.json
  def show
    authorize @message
  end

  # GET /messages/new
  def new
    @message = Message.new(message_params)
    @message.user_id = current_user.id
    @message.entity_id = @message.owner.entity_id
    authorize @message
  end

  # GET /messages/1/edit
  def edit
    authorize @message
  end

  # POST /messages or /messages.json
  def create
    @message = Message.new(message_params)
    @message.user_id = current_user.id
    @message.entity_id = @message.owner.entity_id
    authorize @message

    respond_to do |format|
      if @message.save
        format.turbo_stream { render :create }
        format.html { redirect_to message_url(@message), notice: "Deal message was successfully created." }
        format.json { render :show, status: :created, location: @message }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @message.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /messages/1 or /messages/1.json
  def update
    authorize @message

    respond_to do |format|
      if @message.update(message_params)
        format.html { redirect_to message_url(@message), notice: "Deal message was successfully updated." }
        format.json { render :show, status: :ok, location: @message }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @message.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /messages/1 or /messages/1.json
  def destroy
    authorize @message
    @message.destroy

    respond_to do |format|
      format.html { redirect_to messages_url, notice: "Deal message was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_message
    @message = Message.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def message_params
    params.require(:message).permit(:user_id, :content, :owner_id, :owner_type)
  end
end
