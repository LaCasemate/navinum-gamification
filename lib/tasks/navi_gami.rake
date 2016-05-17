namespace :navi_gami do
  task setup: ['challenges:setup']

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

  namespace :db do
    task undo: :environment do
      ENV['VERSION'] = '20160513092838'
      Rake::Task["db:migrate:down"].invoke
    end
  end
end
