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

  # Job to call callbacks on Navinum API
  class ::NaviGami::APICallbacksJob < ActiveJob::Base
    queue_as :default

    Logger = Sidekiq.logger.level == Logger::DEBUG ? Sidekiq.logger : nil

    def perform(action, object = nil)
      Logger.debug ['Gamification Navinum', action, object]

      case action
      when 'subscription.create'
      when 'user_training.create'
      when 'project.published'
      when 'reservation.create'
      end
    end
  end

  # callback for new subscription
  Subscription.class_eval do
    # I can't use option :on and :if at the same time...unless it triggers on every event
    after_commit ->(subscription) { subscription.navi_gami_callback }, if: :navi_gami_new_subscription?

    def navi_gami_callback
      NaviGami::APICallbacksJob.perform_later('subscription.create', self)
    end

    private
      def navi_gami_new_subscription? # pretty horrible method
        if self.persisted?
          if self.updated_at == self.created_at # if create
            return true
          elsif previous_changes[:expired_at].present? and previous_changes[:expired_at][0].nil? # if update
            return true
          end
        end
        false
      end
  end

  # callback when user validates a training
  UserTraining.class_eval do
    after_commit :navi_gami_callback, on: :create

    private
      def navi_gami_callback
        NaviGami::APICallbacksJob.perform_later('user_training.create', self)
      end
  end

  # callback when project is published well documented
  Project.class_eval do
    after_commit :navi_gami_callback, on: [:create, :update]

    private
      def navi_gami_callback
        if self.project_caos.any? and self.project_image and self.name.present? and self.description.present?
          NaviGami::APICallbacksJob.perform_later('project.published', self)
        end
      end
  end

  # callback when user books a machine
  Reservation.class_eval do
    after_commit :navi_gami_callback, on: :create

    private
      def navi_gami_callback
        NaviGami::APICallbacksJob.perform_later('reservation.create', self) if self.reservation_type == "Machine"
      end
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
