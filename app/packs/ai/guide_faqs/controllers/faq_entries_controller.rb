# frozen_string_literal: true

# FAQ Manager: CapHive support creates, edits, publishes and archives user-guide FAQs, and
# exports or imports them as a spreadsheet. See docs/modules/ai/customer_support_agent/guide_faq_search_prd.md.
class FaqEntriesController < ApplicationController
  before_action :set_faq_entry, only: %i[show edit update destroy publish archive verify]

  def index
    authorize FaqEntry
    @q = policy_scope(FaqEntry).ransack(params[:q])
    entries = @q.result.ordered

    respond_to do |format|
      format.html { @pagy, @faq_entries = pagy(entries, limit: 50) }
      format.xlsx do
        send_data FaqSpreadsheet.export(entries), filename: "faqs_#{Time.zone.now.strftime('%Y%m%d%H%M%S')}.xlsx",
                                                  type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      end
    end
  end

  def show; end

  def new
    @faq_entry = FaqEntry.new(guide_key: params[:guide_key], question: params[:question],
                              faq_group: params[:faq_group].presence || "troubleshooting",
                              source_message_id: params[:source_message_id])
    authorize @faq_entry
  end

  def edit; end

  def create
    @faq_entry = FaqEntry.new(faq_entry_params.merge(created_by: current_user, updated_by: current_user))
    authorize @faq_entry
    if @faq_entry.save
      redirect_to @faq_entry, notice: "FAQ saved as a draft. Publish it to show it on the guide and in the chatbot."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @faq_entry.update(faq_entry_params.merge(updated_by: current_user))
      redirect_to @faq_entry, notice: "FAQ updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @faq_entry.destroy!
    redirect_to faq_entries_path, notice: "Draft FAQ deleted."
  end

  def publish
    if @faq_entry.publish!(current_user)
      redirect_to @faq_entry, notice: "FAQ published. It shows on the guide page and in the chatbot within a minute."
    else
      redirect_to @faq_entry, alert: "Not published: #{@faq_entry.errors.full_messages.to_sentence}"
    end
  end

  def archive
    @faq_entry.archive!(current_user)
    redirect_to @faq_entry, notice: "FAQ archived. It no longer shows on the guide page or in the chatbot."
  end

  def verify
    if @faq_entry.verify!(current_user)
      redirect_to @faq_entry, notice: "FAQ marked as verified."
    else
      redirect_to @faq_entry, alert: "Not verified: #{@faq_entry.errors.full_messages.to_sentence}"
    end
  end

  def import
    authorize FaqEntry
    file = params[:file]
    return redirect_to(faq_entries_path, alert: "Choose an .xlsx file to upload.") unless file.respond_to?(:path)

    result = FaqSpreadsheet.import(file.path, user: current_user)
    flash[result.errors.any? ? :alert : :notice] = ["Import finished: #{result.summary}.", *result.errors.first(20)].join(" ")
    redirect_to faq_entries_path
  rescue ArgumentError => e
    redirect_to faq_entries_path, alert: "Import failed: #{e.message}"
  end

  private

  def set_faq_entry
    @faq_entry = FaqEntry.find(params[:id])
    authorize @faq_entry
  end

  def faq_entry_params
    params.expect(faq_entry: %i[guide_key faq_group position question answer keywords audience source_message_id])
  end
end
