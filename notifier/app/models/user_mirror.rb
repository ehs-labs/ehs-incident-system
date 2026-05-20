# frozen_string_literal: true

module Notifier
  module Models
    class UserMirror < Sequel::Model(:users_mirror)
      # user_id IS the primary key (varchar) — we set it explicitly when
      # upserting, so disable Sequel's default mass-assignment guard.
      unrestrict_primary_key

      plugin :timestamps, update_on_create: true

      def self.upsert(user_id:, **attrs)
        row = where(user_id: user_id).first
        if row
          row.update(attrs.merge(updated_at: Time.now.utc))
        else
          create(attrs.merge(user_id: user_id))
        end
      end
    end
  end
end
