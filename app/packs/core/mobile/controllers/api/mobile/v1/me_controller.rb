# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # The signed-in user, the formats the app must display with, and their push categories.
      # Dates are formatted on the phone with the SAME strftime pattern the website uses for the
      # request's locale (Accept-Language → WithLocale), so the app and website always agree
      # (H4 dd/mm/yyyy for India English, E24 mm/dd/yyyy for US English).
      class MeController < BaseController
        # GET /api/mobile/v1/me
        def show
          authorize current_user, :show_self?, policy_class: MobileSelfPolicy
          render json: me_json
        end

        # PATCH /api/mobile/v1/me/push_preferences — H15
        def push_preferences
          authorize current_user, :update_self?, policy_class: MobileSelfPolicy
          prefs = params.require(:push_preferences).permit(*User::PUSH_CATEGORIES)
          ActiveRecord::Base.connected_to(role: :writing) { current_user.update_push_preferences!(prefs.to_h) }
          render json: me_json
        end

        private

        def personas(user)
          InvestorAdvisor.joins(:entity).where(user_id: user.id).where(entities: { active: true })
                         .pluck("investor_advisors.id", "entities.name")
                         .map { |id, name| { id:, name: } }
        end

        def me_json
          user = current_user
          {
            user: { id: user.id, first_name: user.first_name, last_name: user.last_name, email: user.email },
            region: SiteRegistry.current_code,
            locale: I18n.locale.to_s,
            date_format: I18n.t("date.formats.default"),
            time_format: I18n.t("time.formats.default"),
            investor_name: user.entity&.name,
            advisor: user.has_cached_role?(:investor_advisor),
            # The investors an advisor can switch to — the same list as the website's persona
            # selector (investor_advisors/_personas). Switching uses the website's own
            # POST /investor_advisors/switch?id= (H8).
            personas: personas(user),
            current_persona_id: user.investor_advisor_id,
            push_preferences: user.push_preferences,
            unread_notifications: user.notifications.unread.count,
            device: { id: current_device.id, push_enabled: current_device.push_enabled,
                      push_status: current_device.push_status }
          }
        end
      end
    end
  end
end
