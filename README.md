# Event-Participant Manager

## Deploying
Things to modify
* Gemfile :production group
* config/application-sample.yml (see that file for details)
Run cron jobs
* Run `whenever -w` to create the cron file
* For Heroku, instead use https://addons.heroku.com/marketplace/scheduler ; tasks are listed in `config/schedule.rb`


## Testing

Test by running 'rspec'.


## Image Sources
* calendar http://thenounproject.com/term/calendar/19362/