register_asset "stylesheets/navi_gami.scss"
register_asset "javascripts/navi_gami.coffee.erb"


PLUGIN_NAME ||= "navi_gami".freeze


after_initialize do
  module ::NaviGami
    class Engine < ::Rails::Engine
      #engine_name PLUGIN_NAME
      isolate_namespace ::NaviGami
    end
  end

  NotificationsMailer.class_eval do
    append_view_path "#{Rails.root}/plugins/navi_gami/views"

    def notify_navi_gami_test # dummy code but proof of concept
      @notification = Notification.last
      mail(to: 'test@sleede.com')  # will search for notify_navi_gami_test.html
                                  # will search subject in notifications_mailer.notify_navi_gami_test.subject in translations
    end
  end

  NotificationType.class_eval do
    notification_type_names %w(notify_navi_gami_test)
  end


  class ::NaviGami::MedalsController < ::API::ApiController
    def index
      render json: ['medaille 1', 'medaille 2']
    end
  end

  # DO NOT WORK, DON'T KNOW WHY

  # ::NaviGami::Engine.routes.draw do
  #   resources :medals, only: :index
  # end

  # Fablab::Application.routes.draw do
  #   mount ::NaviGami::Engine, at: "/navi_gami"
  # end

  Fablab::Application.routes.append do
    resources :medals, only: :index, module: :navi_gami
  end
end
