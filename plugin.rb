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

  class ::NaviGami::Challenge < ActiveRecord::Base
    belongs_to :training
    validates :key, uniqueness: { scope: :training_id }

    def medal_id=(val)
      super(val.try(:strip))
    end
  end

  Training.class_eval do
    has_one :challenge, class_name: "::NaviGami::Challenge", dependent: :destroy
    after_create :navi_gami_create_challenge

    private
      def navi_gami_create_challenge
        ::NaviGami::Challenge.create!(key: 'user_training.create', training: self)
      end
  end

  class ::NaviGami::ChallengesController < ::API::ApiController
    before_action :authenticate_user!
    before_action :authorize_admin_only!

    def index
      @challenges = ::NaviGami::Challenge.order(:created_at)
      render json: @challenges.as_json(include: :training)
    end

    def update
      @challenge = ::NaviGami::Challenge.find(params[:id])
      if @challenge.update(challenge_params)
        render json: @challenge.as_json(include: :training)
      else
        render json: @challenge.errors, status: :unprocessable_entity
      end
    end

    private
      def authorize_admin_only!
        (head 403 and return) unless current_user.has_role? :admin
      end

      def challenge_params
        params.require(:challenge).permit(:medal_id, :active)
      end
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
      when 'reservation.machine.create'
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
        NaviGami::APICallbacksJob.perform_later('reservation.machine.create', self) if self.reservation_type == "Machine"
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
    namespace :navi_gami do
      resources :challenges
    end
  end
end
