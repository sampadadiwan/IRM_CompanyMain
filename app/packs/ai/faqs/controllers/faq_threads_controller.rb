class FaqThreadsController < ApplicationController
  before_action :set_faq_thread, only: %i[show create_message]
  after_action :verify_policy_scoped, only: []
  after_action :verify_authorized, only: []
  # GET /faq_threads
  def index
    # List threads or redirect to the most recent one
    @faq_threads = current_user.faq_threads.order(updated_at: :desc)

    if @faq_threads.any?
      redirect_to faq_thread_path(@faq_threads.first)
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        create
      end
    end
  end

  # GET /faq_threads/:id
  def show
    @faq_threads = current_user.faq_threads.order(updated_at: :desc)
    # We will load the view which connects to the ActionCable channel
  end

  # POST /faq_threads
  def create
    @faq_thread = current_user.faq_threads.create!(title: "Support Chat")
    redirect_to faq_thread_path(@faq_thread)
  end

  # POST /faq_threads/:id/create_message
  def create_message
    user_message = params[:message]

    # Save user message to history
    @faq_thread.messages << { role: "user", content: user_message }
    @faq_thread.save!

    # Broadcast user message immediately to the UI
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          "faq_thread_messages",
          partial: "faq_threads/message",
          locals: { role: "user", content: user_message }
        )

        # Trigger the bot response asynchronously
        # We pass the message to the service which should handle the broadcasting
        SupportBotJob.perform_later(@faq_thread.id, user_message)
      end
    end
  end

  private

  def set_faq_thread
    @faq_thread = current_user.faq_threads.find(params[:id])
  end
end
