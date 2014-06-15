task :send_invitations => :environment do

  Invitation.find_each do |invitation|
    e = Event.find invitation.event_id
    if e.full?
      Invitation.where(event_id: e.id).destroy_all
    elsif e.approved?
      eus = e.event_users.where user_id: invitation.user_id
      if eus.any?
        eu = eus.first
        EventMailer.invite(invitation.event, invitation.user).deliver if eu.invited?
      end
    end
    invitation.destroy
  end

end