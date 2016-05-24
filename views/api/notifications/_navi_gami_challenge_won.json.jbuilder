json.title notification.notification_type

description = t('.you_won_a_challenge')

if notification.get_meta_data(:event)
  description += " #{t('.by')}"
  description += " #{t(".events.#{notification.get_meta_data(:event)}")}"
  description += '.'
end

json.description description

json.url notification_url(notification, format: :json)
