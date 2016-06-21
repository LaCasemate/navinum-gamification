### Installation

- in your fab-manager app folder, create a folder and `git clone` this repo into it
- run the rake task `rake navi_gami:setup` which consists in:
  - run the migrations
  - creates challenges (subscription.create, project.published, reservation.machine.create, user_training.create)
  - create a config object which stores configuration of the plugin
- set `navinum_api_login` and `navinum_api_password` in your `secrets.yml`
- restart fab-manager app
- sign in as admin and configure plugin paramaters: `external_space_url, api_url, context_id, universe_id`
- if you want to retroactively give medals based on user actions history on fab-manager, run the task `rake navi_gami:retroactively_push_medals`. **Be sure to run this task after you configurated correctly the plugin parameters.**
- enjoy

### Architecture

This plugin partially reproduces the tree view of a Rails app:
- `assets` contains js code, stylesheets and angular templates
- `config/locales` contains locales which permit internationalization
- `db/migrate` contains the plugin's migrations, those migrations enable creating new tables and/or adding new columns to existing ones
- `lib/tasks` contains the rake tasks, including tasks to install/init the plugin if necessary
- `views` contains regular views

All the code of the plugin lives in the **plugin.rb** file and does a lot of things:
- registering assets
- registering code insertions (needed if you wants to override already existing views of Fab-manager)
- defining plugin's ruby classes (models, controllers, jobs, ect)
- overriding already existing classes by reopening them
- defining its routes
