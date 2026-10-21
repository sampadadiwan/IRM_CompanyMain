# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # GET /api/mobile/v1/documents?q=&commitment_id=&to_sign=&page=&fund_manager_id= — the Documents tab
      # (E19, E20). Only the LIST is mobile-specific: the website has no JSON endpoint listing an
      # LP's documents across their commitments, calls and distributions. Opening a document
      # uses the website's own GET /documents/:id.json (records "viewed by", H7).
      class DocumentsController < BaseController
        def index
          skip_authorization # every row is limited by MobileDocuments' scoped owner clause
          docs = MobileDocuments.new(user: current_user, scope: method(:policy_scope), fund_manager_id:)
                                .list(commitment_id: params[:commitment_id], query: params[:q].to_s.first(100),
                                      to_sign: ActiveModel::Type::Boolean.new.cast(params[:to_sign]))
          items, next_page = paginate(docs)
          render json: { items: items.map { |doc| MobileDocumentJson.summary(doc) }, next_page:, fund_manager_id: }
        end
      end
    end
  end
end
