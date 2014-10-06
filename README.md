# Event-Participant Manager


## About
EPM is a Rails-based application for managing events and participants within an organization, where both are spread across a region and there are more participants than are needed for a typical event. It handles the who/where/when. Each event has basic details (date-times, name, description, location), and a coordinator. Participants are invited to events; EPM handles the min/max participants per event, waitlisting, cancellation, etc., as well as keeping attendance after events have occurred. There are email notifications for event changes or cancellation, reminders, etc.


## Interested in EPM?
Contact Michael Fagan - see http://faganm.com/


## Who is using EPM?
* Not Far From the Tree (using a variant) https://github.com/not-far-from-the-tree/epm
* The Toronto Clothing Repairathon http://repairathon.com/


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