# frozen_string_literal: true

class ReviewableSpamWardenSerializer < ReviewableSerializer
  attributes :spam_warden_scan, :spam_warden_username, :spam_warden_user_id

  def spam_warden_scan
    scan = object.spam_warden_scan
    SpamWardenScanSerializer.new(scan, scope: scope, root: false).as_json if scan
  end

  def spam_warden_username
    object.target&.username
  end

  def spam_warden_user_id
    object.target_id
  end
end
