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
end
