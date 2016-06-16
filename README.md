### Installation

- in your fab-manager app folder, create a folder and `git clone` this repo into it
- run the rake task `rake navi_gami:setup` which consists in:
  - run the migrations
  - creates challenges (subscription.create, project.published, reservation.machine.create, user_training.create)
  - create a config object which stores configuration of the plugin
- restart fab-manager app
- sign in as admin and configure plugin paramaters: `external_space_url, api_url, context_id, universe_id`
- if you want to retroactively give medals based on user actions history on fab-manager, run the task `rake navi_gami:retroactively_push_medals`. **Be sure to run this task after you configurated correctly the plugin parameters.**
- enjoy
