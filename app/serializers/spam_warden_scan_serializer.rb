# frozen_string_literal: true

class SpamWardenScanSerializer < ApplicationSerializer
  attributes :id,
             :user_id,
             :username,
             :status,
             :decision,
             :action_taken,
             :source,
             :created_at,
             :reviewable_id,
             :error_code,
             :evidence,
             :policy

  def username
    object.user&.username
  end

  def evidence
    object.evidence.map { |field, data| data.merge("field" => field) }
  end
end
