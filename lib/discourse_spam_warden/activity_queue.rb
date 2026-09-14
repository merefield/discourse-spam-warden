# frozen_string_literal: true

module DiscourseSpamWarden
  class ActivityQueue
    RESERVATION_SECONDS = 6.hours.to_i

    def self.enqueue(user_id, delay: 1.minute, attempt: 0)
      DB.after_commit do
        token = SecureRandom.hex(16)
        if Discourse.redis.set(key(user_id), token, nx: true, ex: RESERVATION_SECONDS)
          begin
            Jobs.enqueue_in(
              delay,
              :spam_warden_check,
              user_id: user_id,
              source: "activity",
              activity_token: token,
              attempt: attempt,
            )
          rescue StandardError
            release(user_id, token)
            raise
          end
        end
      end
    end

    def self.release(user_id, token)
      return unless token

      Discourse.redis.eval(
        "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) end",
        keys: [Discourse.redis.namespace_key(key(user_id))],
        argv: [token],
      )
    end

    def self.key(user_id)
      "spam_warden:activity:#{user_id}"
    end
  end
end
