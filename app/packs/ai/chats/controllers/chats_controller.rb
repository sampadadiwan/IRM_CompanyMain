class ChatsController < ApplicationController
  before_action :set_chat, only: %i[show edit update destroy send_message]

  # GET /chats
  def index
    @chats = policy_scope(Chat.all).includes(:user)
    @chats = filter_params(@chats, :owner_id, :owner_type)
    @chats = @chats.page(params[:page]) unless params[:format] == "xlsx"
  end

  # GET /chats/1
  def show; end

  # GET /chats/new
  def new
    @chat = Chat.new
    @chat.user_id = current_user.id
    @chat.entity_id = current_user.entity_id
    authorize @chat
  end

  # GET /chats/1/edit
  def edit; end

  # POST /chats
  def create
    @chat = Chat.new(chat_params)
    @chat.user_id = current_user.id
    @chat.entity_id = current_user.entity_id
    authorize @chat
    if @chat.save
      redirect_to @chat, notice: "Chat was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /chats/1
  def update
    if @chat.update(chat_params)
      redirect_to @chat, notice: "Compliance rule was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def send_message
    ChatStreamJob.perform_later(@chat.id, params[:user_content])
  end

  # DELETE /chats/1
  def destroy
    @chat.destroy!
    redirect_to chats_url, notice: "Compliance rule was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_chat
    @chat = Chat.find(params[:id])
    authorize @chat
  end

  # Only allow a list of trusted parameters through.
  def chat_params
    params.require(:chat).permit(:name, :user_content)
  end
end
