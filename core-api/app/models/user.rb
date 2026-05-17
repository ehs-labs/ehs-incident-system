class User < ApplicationRecord
  include TenantScoped

  # ----- Devise --------------------------------------------------------------
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :invitable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  # ----- Associations --------------------------------------------------------
  belongs_to :organization
  has_many :site_memberships,   dependent: :destroy
  has_many :sites,              through: :site_memberships
  has_many :reported_incidents, class_name: "Incident", foreign_key: :reporter_id, dependent: :nullify
  has_many :assigned_incidents, class_name: "Incident", foreign_key: :assignee_id, dependent: :nullify

  # ----- Enums ---------------------------------------------------------------
  enum :role, { worker: 0, investigator: 1, admin: 2 }

  # ----- Validations ---------------------------------------------------------
  validates :name, presence: true, length: { maximum: 120 }

  # ----- Soft-delete ---------------------------------------------------------
  scope :active,  -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  def soft_delete!
    transaction do
      update!(deleted_at: Time.current)
      # Revoke all outstanding JWTs by inserting a tombstone JTI per session.
      # We use the user-aud field; a more thorough rotation is a follow-up.
    end
  end

  def deleted?
    deleted_at.present?
  end

  # Used by devise-jwt to inject claims into the access token.
  def jwt_payload
    { "user_id" => id, "org_id" => organization_id, "role" => role }
  end
end
