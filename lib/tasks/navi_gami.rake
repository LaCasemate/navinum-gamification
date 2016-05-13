namespace :navi_gami do
  namespace :challenges do
    task init: :environment do
      NaviGami::Challenge.create!(key: 'subscription.create')
      NaviGami::Challenge.create!(key: 'project.published')
      NaviGami::Challenge.create!(key: 'reservation.machine.create')

      Training.order(:created_at).each do |training|
        NaviGami::Challenge.create!(key: 'user_training.create', training: training)
      end
    end
  end
end
