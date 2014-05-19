task :send_invitations => :environment do

  Invitation.find_each do |invitation|
    e = Event.find invitation.event
    if e.approved?
      eu = e.event_users.find_by user_id: invitation.user_id
      EventMailer.invite(invitation.event, invitation.user).deliver if eu.invited?
    end
    invitation.destroy
  end

end