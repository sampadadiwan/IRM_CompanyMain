class ChatsController < ApplicationController
  before_action :set_chat, only: %i[show edit update destroy send_message]

  # GET /chats
  def index
    @chats = policy_scope(Chat.all).includes(:user)
    @chats = filter_params(@chats, :owner_id, :owner_type)
    @pagy, @chats = pagy(@chats) unless params[:format] == "xlsx"
  end

  # GET /chats/1 — on the chat kit (openspec/changes/ai-chat-kit, card ①): the record's chats beside
  # this one (the same chats the Analysis tab lists), and this chat's questions and answers.
  def show
    @rows = AiChatRows.for_chats(policy_scope(Chat.all).where(owner: @chat.owner), url: ->(chat) { chat_path(chat) })
    # An assistant message without content is a tool-call step, not an answer, so it is not drawn.
    @items = @chat.messages.where(role: %w[user assistant]).order(:created_at)
                  .reject { |m| m.role == "assistant" && m.content.blank? }
                  .map { |m| AiChatItem.from_message(m) }
  end

  # GET /chats/new
  def new
    @chat = Chat.new(chat_params)
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
    @chat.model = ENV.fetch('DEFAULT_MODEL', nil)
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
      redirect_to @chat, notice: "Chat was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # POST /chats/1/send_message — H5: the question and a pending answer join the thread at once
  # (send_message.turbo_stream); ChatStreamJob streams the answer into the pending one by request id.
  def send_message
    @query = params[:user_content].to_s.strip
    # A blank question is never sent (the box blocks it too).
    return head(:unprocessable_entity) if @query.blank?

    @request_id = SecureRandom.hex(12)
    ChatStreamJob.perform_later(@chat.id, @query, document_id: params[:document_id], request_id: @request_id)
  end

  # DELETE /chats/1
  def destroy
    @chat.destroy!
    if @chat.owner
      redirect_to @chat.owner, notice: "Chat was successfully destroyed.", status: :see_other
    else
      redirect_to chats_url, notice: "Chat was successfully destroyed.", status: :see_other
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_chat
    @chat = Chat.find(params[:id])
    authorize @chat
  end

  # Only allow a list of trusted parameters through.
  def chat_params
    params.require(:chat).permit(:name, :user_content, :owner_id, :owner_type, :model)
  end
end
