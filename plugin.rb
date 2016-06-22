# encoding: utf-8

register_asset "stylesheets/navi_gami.scss"
register_asset "javascripts/navi_gami.coffee.erb"


PLUGIN_NAME ||= "navi_gami".freeze

register_code_insertion 'html.user.profile', <<-HTML
  <div id="navi_gami_hook">
    <div ng-controller="NGProfileDataController as vm">
      <div ng-if="vm.status">
        <a ng-href="{{ vm.externalSpaceUrl }}" target="_blank">
          <img ng-src="{{ vm.status.image_url }}" alt="" />
          <span class="">{{ vm.status.label }}</span>
          <p>
            {{ vm.status.description }}
          </p>
        </a>
      </div>
    </div>
  </div>
HTML

register_code_insertion 'yml.schedule',
<<-YAML
navi_gami_update_users:
  cron: "0 3 * * *"
  class: "::NaviGami::UpdateUsersDataJob"
  queue: default
YAML


after_initialize do
  module ::NaviGami
    class Engine < ::Rails::Engine
      #engine_name PLUGIN_NAME
      isolate_namespace ::NaviGami
    end

    module Events
      SUBSCRIPTION_CREATE = 'subscription.create'.freeze
      USER_TRAINING_CREATE = 'user_training.create'.freeze
      PROJECT_PUBLISHED = 'project.published'.freeze
      RESERVATION_MACHINE_CREATE = 'reservation.machine.create'.freeze
    end
  end

  class ::NaviGami::MissingConfigError < StandardError; end;
  class ::NaviGami::MissingUserUIDError < StandardError; end;

  NotificationType.class_eval do
    notification_type_names %w(navi_gami_challenge_won)
  end

  # concern for controller
  module ::NaviGami::ControllersConcern
    private
      def authorize_admin_only!
        (head 403 and return) unless current_user.has_role? :admin
      end
  end

  # MODEL + CTRL of Config
  class ::NaviGami::Config < ActiveRecord::Base
    def api_url=(val)
      super(without_end_slash(val).try(:strip))
    end

    def external_space_url=(val)
      super(without_end_slash(val).try(:strip))
    end

    def context_id=(val)
      super(val.try(:strip))
    end

    def universe_id=(val)
      super(val.try(:strip))
    end

    private
      def without_end_slash(url)
        return url if url.nil?
        url[-1] == "/" ? url[0..-2] : url
      end
  end

  class ::NaviGami::ConfigsController < ApplicationController
    include ::NaviGami::ControllersConcern
    before_action :authenticate_user!
    before_action :authorize_admin_only!

    def show
      render json: ::NaviGami::Config.first
    end

    def update
      @config = ::NaviGami::Config.first
      if @config.update(config_params)
        render json: @config
      else
        render json: { errors: @config.errors }, status: :unprocessable_entity
      end
    end

    private
      def config_params
        params.require(:config).permit(:external_space_url, :api_url, :universe_id, :context_id)
      end
  end

  # MODEL + CTRL of Challenge
  class ::NaviGami::Challenge < ActiveRecord::Base
    belongs_to :training
    validates :key, uniqueness: { scope: :training_id }

    def medal_id=(val)
      super(val.try(:strip))
    end
  end

  class ::NaviGami::ChallengesController < ApplicationController
    include ::NaviGami::ControllersConcern
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
        render json: { errors: @challenge.errors }, status: :unprocessable_entity
      end
    end

    private
      def challenge_params
        params.require(:challenge).permit(:medal_id, :active)
      end
  end

  class ::NaviGami::GamificationDataProxyController < ApplicationController
    def profile_data
      config = ::NaviGami::Config.first

      body, raw_response = ::NaviGami::API::Visitor.show(guid: params[:user_uid])
      body = body[0]

      if body
        visitor_status_data = body.dig("VisiteurUnivers", config.universe_id, "VisiteurStatus").try(:[], 0)
      end

      if visitor_status_data
        universe_status = visitor_status_data["UniversStatus"]
      end

      if universe_status
        status = {
          label: universe_status["libelle"],
          description: universe_status["description"],
          image_url: universe_status["image1"]
        }
      else
        status = nil
      end

      render json: {
        external_space_url: config.external_space_url,
        status: status
      }
    end
  end

  # Micro API wrapper to consume API

  module ::NaviGami::API
    class << self
      attr_accessor :config

      def config
        @config ||= Config.new
      end
    end

    class Error < StandardError; end;

    def self.configure
      yield config
    end

    def self.handle_response(response)
      if response.code.to_i >= 500
        raise ::NaviGami::API::Error
      else
        return JSON.parse(response.body), response
      end
    end

    def self.post(uri_string, body)
      uri = URI(uri_string)
      req = Net::HTTP::Post.new(uri, initheader = { 'Content-Type' => 'application/json' })
      req.basic_auth ::NaviGami::API.config.login, ::NaviGami::API.config.password
      req.body = body.to_json
      handle_response(Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) })
    end

    def self.get(uri_string)
      uri = URI(uri_string)
      req = Net::HTTP::Get.new(uri)
      req.basic_auth ::NaviGami::API.config.login, ::NaviGami::API.config.password
      handle_response(Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) })
    end

    class Config
      attr_accessor :base_uri, :login, :password

      def initialize
        @base_uri = ::NaviGami::Config.first.api_url
        @login = Rails.application.secrets.navinum_api_login
        @password = Rails.application.secrets.navinum_api_password
      end
    end

    module VisitorMedal
      def self.create(body)
        full_uri = "#{::NaviGami::API.config.base_uri}/visiteur_medaille/create"
        ::NaviGami::API.post(full_uri, body)
      end

      def self.index(visiteur_id:)
        query_params = { visiteur_id: visiteur_id }
        full_uri = "#{::NaviGami::API.config.base_uri}/visiteur_medaille?#{query_params.to_query}"
        ::NaviGami::API.get(full_uri)
      end
    end

    module Visitor
      def self.show(guid:, with_univers: 1)
        query_params = { guid: guid, with_univers: with_univers}
        full_uri = "#{::NaviGami::API.config.base_uri}/visiteur?#{query_params.to_query}"
        ::NaviGami::API.get(full_uri)
      end
    end

    module CSP
      def self.index
        full_uri = "#{::NaviGami::API.config.base_uri}/csp"
        ::NaviGami::API.get(full_uri)
      end
    end
  end

  # Job to call callbacks on Navinum API
  class ::NaviGami::APICallbacksJob < ActiveJob::Base
    queue_as :default

    Logger = Sidekiq.logger

    def perform(action, object = nil)
      Logger.info ['Gamification Navinum Job', action, object]

      navi_config = ::NaviGami::Config.first

      request_body = { contexte_id: navi_config.context_id, univers_id: navi_config.universe_id }

      user = object.try(:user) || object.author

      raise ::NaviGami::MissingUserUIDError if user.uid.blank?

      case action
      when ::NaviGami::Events::SUBSCRIPTION_CREATE, ::NaviGami::Events::PROJECT_PUBLISHED, ::NaviGami::Events::RESERVATION_MACHINE_CREATE
        challenge = ::NaviGami::Challenge.find_by(key: action)
      when ::NaviGami::Events::USER_TRAINING_CREATE
        challenge = object.training.challenge
      end

      request_body = request_body.merge({ visiteur_id: user.uid, medaille_id: challenge.medal_id })

      if challenge.active? and challenge.medal_id
        user_medals = ::NaviGami::API::VisitorMedal.index(visiteur_id: user.uid)[0]

        if user_medals.any? { |medal| medal["medaille_id"] == challenge.medal_id }
          Logger.info ['Navinum API', "User with UID=#{user.uid} already has medal with uid=#{challenge.medal_id}"]
        else
          Logger.info ['Navinum API request body sent', request_body]
          response_body, raw_response = ::NaviGami::API::VisitorMedal.create(request_body)
          Logger.info ['Navinum API response', raw_response.code, raw_response.try(:body)]

          if (raw_response.code.to_i >= 200) and (raw_response.code.to_i < 300)
            notification = Notification.new(meta_data: { event: action })
            notification.send_notification(type: :navi_gami_challenge_won, attached_object: object).to(user).deliver_later
          end
        end
      else
        Logger.info ['Gamification Navinum', "no request made because challenge isn't active or challenge doesn't have medal_id associated with."]
      end
    end
  end

  # association between training and challenge, with callback to create challenge when a training is created
  Training.class_eval do
    has_one :challenge, class_name: "::NaviGami::Challenge", dependent: :destroy
    after_create :navi_gami_create_challenge

    private
      def navi_gami_create_challenge
        ::NaviGami::Challenge.create!(key: ::NaviGami::Events::USER_TRAINING_CREATE, training: self)
      end
  end

  # callback for new subscription
  Subscription.class_eval do
    # I can't use option :on and :if at the same time...unless it triggers on every event
    after_commit ->(subscription) { subscription.navi_gami_callback }, if: :navi_gami_new_subscription?

    def navi_gami_callback
      ::NaviGami::APICallbacksJob.perform_later(::NaviGami::Events::SUBSCRIPTION_CREATE, self)
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
        NaviGami::APICallbacksJob.perform_later(::NaviGami::Events::USER_TRAINING_CREATE, self)
      end
  end

  # callback when project is published well documented
  Project.class_eval do
    after_commit :navi_gami_callback, on: [:create, :update]

    private
      def navi_gami_callback
        if self.project_caos.any? and self.machines.any? and self.name.present? and self.description.present?
          NaviGami::APICallbacksJob.perform_later(::NaviGami::Events::PROJECT_PUBLISHED, self)
        end
      end
  end

  # callback when user books a machine
  Reservation.class_eval do
    after_commit :navi_gami_callback, on: :create

    private
      def navi_gami_callback
        NaviGami::APICallbacksJob.perform_later(::NaviGami::Events::RESERVATION_MACHINE_CREATE, self) if self.reservable_type == "Machine"
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
      resources :challenges, only: [:index, :update]
      resource :config, only: [:show, :update]

      namespace :gamification_data_proxy do
        get :profile_data
      end
    end
  end

  # Job to update users' account data with Navinum API
  class ::NaviGami::UpdateUsersDataJob
    include Sidekiq::Worker
    sidekiq_options queue: 'default', retry: true

    Logger = Sidekiq.logger

    def perform
      Logger.info ['Navinum UPDATE USERS JOB']

      csps, raw_response = ::NaviGami::API::CSP.index # get categories socioprofessionnelles

      profile_mapping = Hash[OAuth2Mapping.where(local_model: "profile").pluck(:local_field, :api_field)]
      user_mapping = Hash[OAuth2Mapping.where(local_model: "user").pluck(:local_field, :api_field)]

      User.where.not(uid: nil).find_in_batches(batch_size: 50) do |group|
        uids = group.map(&:uid).join(',')

        batch_users_response, raw_response = ::NaviGami::API::Visitor.show(guid: uids, with_univers: 0)

        group.each do |user|
          api_user_response = batch_users_response.find { |user_response| user_response["guid"] == user.uid }

          #Logger.info ['API RESPONSE', api_user_response]

          if api_user_response

            whitelisted_changes = {}

            if user_mapping.key?("username")
              unless User.where.not(id: user.id).where(username: api_user_response[user_mapping["username"]]).any?
                whitelisted_changes["username"] = api_user_response[user_mapping["username"]]
              end
            end

            if user_mapping.key?("email")
              unless User.where.not(id: user.id).where(email: api_user_response[user_mapping["email"]]).any?
                whitelisted_changes["email"] = api_user_response[user_mapping["email"]]
              end
            end

            whitelisted_changes["profile_attributes"] = {}

            if profile_mapping.key?("first_name")
              if api_user_response[profile_mapping["first_name"]].present? and api_user_response[profile_mapping["first_name"]].length <= 30
                whitelisted_changes["profile_attributes"]["first_name"] = api_user_response[profile_mapping["first_name"]]
              end

              if api_user_response[profile_mapping["last_name"]].present? and api_user_response[profile_mapping["last_name"]].length <= 30
                whitelisted_changes["profile_attributes"]["last_name"] = api_user_response[profile_mapping["last_name"]]
              end
            end

            if profile_mapping.key?("gender")
              if api_user_response[profile_mapping["gender"]].upcase.in? ['H','F']
                whitelisted_changes["profile_attributes"]["gender"] = (api_user_response[profile_mapping["gender"]].upcase == 'H') ? true : false
              end
            end

            if profile_mapping.key?("birthday")
              begin
                whitelisted_changes["profile_attributes"]["birthday"] = Date.parse(api_user_response[profile_mapping["birthday"]])
              rescue ArgumentError, TypeError
              end
            end

            if profile_mapping.key?("phone")
              if api_user_response[profile_mapping["phone"]].present? and !!(api_user_response[profile_mapping["phone"]] =~ /\A\d+\z/) # test if numeric
                whitelisted_changes["profile_attributes"]["phone"] = api_user_response[profile_mapping["phone"]]
              end
            end

            if profile_mapping.key?("website") and api_user_response[profile_mapping["website"]].present?
              whitelisted_changes["profile_attributes"]["website"] = api_user_response[profile_mapping["website"]]
            end

            if profile_mapping.key?("facebook") and api_user_response[profile_mapping["facebook"]].present?
              whitelisted_changes["profile_attributes"]["facebook"] = api_user_response[profile_mapping["facebook"]]
            end

            if profile_mapping.key?("twitter") and api_user_response[profile_mapping["twitter"]].present?
              whitelisted_changes["profile_attributes"]["twitter"] = api_user_response[profile_mapping["twitter"]]
            end

            if profile_mapping.key?("google_plus") and api_user_response[profile_mapping["google_plus"]].present?
              whitelisted_changes["profile_attributes"]["google_plus"] = api_user_response[profile_mapping["google_plus"]]
            end

            if profile_mapping.key?("linkedin") and api_user_response[profile_mapping["linkedin"]].present?
              whitelisted_changes["profile_attributes"]["linkedin"] = api_user_response[profile_mapping["linkedin"]]
            end

            if profile_mapping.key?("instagram") and api_user_response[profile_mapping["instagram"]].present?
              whitelisted_changes["profile_attributes"]["instagram"] = api_user_response[profile_mapping["instagram"]]
            end

            if profile_mapping.key?("youtube") and api_user_response[profile_mapping["youtube"]].present?
              whitelisted_changes["profile_attributes"]["youtube"] = api_user_response[profile_mapping["youtube"]]
            end

            if profile_mapping.key?("dailymotion") and api_user_response[profile_mapping["dailymotion"]].present?
              whitelisted_changes["profile_attributes"]["dailymotion"] = api_user_response[profile_mapping["dailymotion"]]
            end

            if profile_mapping.key?("job") and api_user_response[profile_mapping["job"]].present?
              csp = csps.find { |csp| csp["guid"] == api_user_response[profile_mapping["job"]] }
              if csp
                whitelisted_changes["profile_attributes"]["job"] = csp["libelle"]
              end
            end

            Logger.info ['changes:', whitelisted_changes]

            user_update_params = whitelisted_changes.except("profile_attributes")

            Logger.info ['user update params', user_update_params]

            profile_update_params = user.profile.attributes.except("created_at", "updated_at", "user_id").merge(whitelisted_changes["profile_attributes"])

            Logger.info ['profile update params', profile_update_params]

            if user.update(user_update_params)
              Logger.info ["User with id #{user.id} successfully updated"]
            else
              Logger.info ["User with id #{user.id} not updated because of following errors", user.errors]
            end

            user.profile.assign_attributes(profile_update_params)

            if user.profile.save(validate: false)
              Logger.info ["Profile with id #{user.profile.id} successfully updated"]
            else
              Logger.info ["Profile with id #{user.profile.id} not updated"]
            end

            if profile_mapping.key?("avatar")
              user_avatar = if user.profile.user_avatar
                user.profile.user_avatar
              else
                user.profile.build_user_avatar
              end
              user_avatar.remote_attachment_url = api_user_response[profile_mapping["avatar"]]
              user_avatar.save
            end
          end
        end
      end
    end
  end
end
