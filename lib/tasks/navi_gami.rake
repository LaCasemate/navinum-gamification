namespace :navi_gami do
  task setup: ['challenges:setup', 'config:setup'] # to be executed after db:migrate

  task undo_setup: ['db:undo']

  namespace :challenges do
    task setup: :environment do
      NaviGami::Challenge.create!(key: 'subscription.create')
      NaviGami::Challenge.create!(key: 'project.published')
      NaviGami::Challenge.create!(key: 'reservation.machine.create')

      Training.order(:created_at).each do |training|
        NaviGami::Challenge.create!(key: 'user_training.create', training: training)
      end
    end
  end

  namespace :config do
    task setup: :environment do
      config = NaviGami::Config.first
      NaviGami::Config.create! unless config
    end
  end

  namespace :db do
    task undo: :environment do
      ENV['VERSION'] = '20160513092838'
      Rake::Task["db:migrate:down"].invoke

      Rake::Task["db:migrate:down"].reenable

      ENV['VERSION'] = '20160517091119'
      Rake::Task["db:migrate:down"].invoke
    end
  end

  task retroactively_push_medals: :environment do
    warn "info: be sure to configure medal_id of challenges before running this task"
    Subscription.find_each { |subscription| subscription.send(:navi_gami_callback) }
    UserTraining.find_each { |user_training| user_training.send(:navi_gami_callback) }
    Project.find_each { |project| project.send(:navi_gami_callback) }
    Reservation.where(reservable_type: "Machine").select('distinct on (reservations.user_id) reservations.*').each { |reservation| reservation.send(:navi_gami_callback) }
  end

  task test_update_user: :environment do
    profile_mapping = Hash[OAuth2Mapping.where(local_model: "profile").pluck(:local_field, :api_field)]
    user_mapping = Hash[OAuth2Mapping.where(local_model: "user").pluck(:local_field, :api_field)]

    user = User.last

    before_update_user_attrs = user.attributes
    before_update_profile_attrs = user.profile.attributes

    whitelist_changes = {}

    if user_mapping.key?("username")
      unless User.where.not(id: user.id).where(username: RESPONSE[user_mapping["username"]]).any?
        whitelist_changes["username"] = RESPONSE[user_mapping["username"]]
      end
    end

    if user_mapping.key?("email")
      unless User.where.not(id: user.id).where(email: RESPONSE[user_mapping["email"]]).any?
        whitelist_changes["email"] = RESPONSE[user_mapping["email"]]
      end
    end

    whitelist_changes["profile_attributes"] = {}

    if profile_mapping.key?("first_name")
      if RESPONSE[profile_mapping["first_name"]].present? and RESPONSE[profile_mapping["first_name"]].length <= 30
        whitelist_changes["profile_attributes"]["first_name"] = RESPONSE[profile_mapping["first_name"]]
      end

      if RESPONSE[profile_mapping["last_name"]].present? and RESPONSE[profile_mapping["last_name"]].length <= 30
        whitelist_changes["profile_attributes"]["last_name"] = RESPONSE[profile_mapping["last_name"]]
      end
    end

    if profile_mapping.key?("gender")
      if RESPONSE[profile_mapping["gender"]].upcase.in? ['H','F']
        whitelist_changes["profile_attributes"]["gender"] = (RESPONSE[profile_mapping["gender"]].upcase == 'H') ? true : false
      end
    end

    if profile_mapping.key?("birthday")
      begin
        whitelist_changes["profile_attributes"]["birthday"] = Date.parse(RESPONSE[profile_mapping["birthday"]])
      rescue ArgumentError
      end
    end

    if profile_mapping.key?("phone")
      if RESPONSE[profile_mapping["phone"]].present? and !!(RESPONSE[profile_mapping["phone"]] =~ /\A\d+\z/) # test if numeric
        whitelist_changes["profile_attributes"]["phone"] = RESPONSE[profile_mapping["phone"]]
      end
    end

    if profile_mapping.key?("website")
      whitelist_changes["profile_attributes"]["website"] = RESPONSE[profile_mapping["website"]]
    end

    if profile_mapping.key?("facebook")
      whitelist_changes["profile_attributes"]["facebook"] = RESPONSE[profile_mapping["facebook"]]
    end

    if profile_mapping.key?("twitter")
      whitelist_changes["profile_attributes"]["twitter"] = RESPONSE[profile_mapping["twitter"]]
    end

    if profile_mapping.key?("google_plus")
      whitelist_changes["profile_attributes"]["google_plus"] = RESPONSE[profile_mapping["google_plus"]]
    end

    if profile_mapping.key?("linkedin")
      whitelist_changes["profile_attributes"]["linkedin"] = RESPONSE[profile_mapping["linkedin"]]
    end

    if profile_mapping.key?("instagram")
      whitelist_changes["profile_attributes"]["instagram"] = RESPONSE[profile_mapping["instagram"]]
    end

    if profile_mapping.key?("youtube")
      whitelist_changes["profile_attributes"]["youtube"] = RESPONSE[profile_mapping["youtube"]]
    end

    if profile_mapping.key?("dailymotion")
      whitelist_changes["profile_attributes"]["dailymotion"] = RESPONSE[profile_mapping["dailymotion"]]
    end

    if profile_mapping.key?("avatar")
      user_avatar = if user.profile.user_avatar
        user.profile.user_avatar
      else
        user.profile.build_user_avatar
      end
      user_avatar.remote_attachment_url = RESPONSE[profile_mapping["avatar"]]
      user_avatar.save
    end

  end
end
