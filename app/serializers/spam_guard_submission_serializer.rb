# frozen_string_literal: true

class SpamGuardSubmissionSerializer < ApplicationSerializer
  attributes :id,
             :status,
             :attempts,
             :approved_at,
             :last_attempt_at,
             :completed_at,
             :error_code,
             :events

  def events
    actor_ids = object.events.filter_map { |event| event["actor_id"] }.uniq
    return object.events if actor_ids.empty?

    usernames = User.where(id: actor_ids).pluck(:id, :username).to_h
    object.events.map { |event| event.merge("actor_username" => usernames[event["actor_id"]]) }
  end
end
