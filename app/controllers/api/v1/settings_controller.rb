module Api
  module V1
    class SettingsController < BaseController
      def show
        render json: SettingSerializer.new(Setting.instance, currency: ShopInfo.currency).as_json
      end

      def update
        setting = Setting.instance
        setting.update!(setting_params)
        render json: SettingSerializer.new(setting, currency: ShopInfo.currency).as_json
      end

      private

      def setting_params
        params.require(:settings).permit(
          :inventory_threshold,
          :max_price_percentage,
          :review_frequency,
          :ai_behavior_prompt,
          :auto_pricing_enabled,
          :fallback_pricing_enabled,
          :price_restoration_enabled
        )
      end
    end
  end
end
