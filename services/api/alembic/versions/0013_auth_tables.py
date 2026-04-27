"""auth foundation tables

Revision ID: 0013
Revises: 0012
Create Date: 2026-04-27

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None

_IP_ADDRESS_TYPE = sa.String(length=64).with_variant(postgresql.INET(), "postgresql")
_JSON_LIST_TYPE = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")


def upgrade() -> None:
    op.create_table(
        "auth_identities",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("identity_type", sa.String(length=32), nullable=False),
        sa.Column("identity_value", sa.String(length=320), nullable=False),
        sa.Column("identity_value_normalized", sa.String(length=320), nullable=False),
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("is_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_auth_identities_person_id_status",
        "auth_identities",
        ["person_id", "status"],
    )
    op.create_index(
        "ix_auth_identities_type_normalized_status",
        "auth_identities",
        ["identity_type", "identity_value_normalized", "status"],
    )

    op.create_table(
        "auth_factors",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "identity_id",
            sa.Uuid(),
            sa.ForeignKey("auth_identities.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column("factor_type", sa.String(length=32), nullable=False),
        sa.Column("display_label", sa.String(length=128), nullable=True),
        sa.Column("secret_ref", sa.String(length=255), nullable=True),
        sa.Column("credential_hash", sa.String(length=255), nullable=True),
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("is_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_auth_factors_person_id_status",
        "auth_factors",
        ["person_id", "status"],
    )
    op.create_index(
        "ix_auth_factors_identity_id_status",
        "auth_factors",
        ["identity_id", "status"],
    )

    op.create_table(
        "auth_challenges",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column(
            "identity_id",
            sa.Uuid(),
            sa.ForeignKey("auth_identities.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column("factor_type", sa.String(length=32), nullable=False),
        sa.Column("challenge_type", sa.String(length=32), nullable=False),
        sa.Column("delivery_channel", sa.String(length=32), nullable=True),
        sa.Column("code_hash", sa.String(length=255), nullable=True),
        sa.Column("attempt_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("max_attempts", sa.Integer(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("ip_address", _IP_ADDRESS_TYPE, nullable=True),
        sa.Column("user_agent", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_auth_challenges_person_id_status",
        "auth_challenges",
        ["person_id", "status"],
    )
    op.create_index(
        "ix_auth_challenges_identity_id_status",
        "auth_challenges",
        ["identity_id", "status"],
    )

    op.create_table(
        "auth_sessions",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("session_token_hash", sa.String(length=255), nullable=False),
        sa.Column("refresh_token_hash", sa.String(length=255), nullable=True),
        sa.Column("auth_strength", sa.String(length=32), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoke_reason", sa.String(length=128), nullable=True),
        sa.Column("ip_address", _IP_ADDRESS_TYPE, nullable=True),
        sa.Column("user_agent", sa.Text(), nullable=True),
        sa.Column("device_id", sa.String(length=128), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.UniqueConstraint("session_token_hash", name="uq_auth_sessions_session_token_hash"),
        sa.UniqueConstraint("refresh_token_hash", name="uq_auth_sessions_refresh_token_hash"),
    )
    op.create_index(
        "ix_auth_sessions_person_id_expires_at",
        "auth_sessions",
        ["person_id", "expires_at"],
    )

    op.create_table(
        "auth_policies",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column("subject_type", sa.String(length=32), nullable=False),
        sa.Column("subject_value", sa.String(length=128), nullable=False),
        sa.Column("allowed_factor_types", _JSON_LIST_TYPE, nullable=False),
        sa.Column("min_factor_count", sa.Integer(), nullable=False),
        sa.Column(
            "require_verified_identity",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column(
            "require_vpn",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column("session_ttl_minutes", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_auth_policies_subject_status",
        "auth_policies",
        ["subject_type", "subject_value", "status"],
    )


def downgrade() -> None:
    op.drop_index("ix_auth_policies_subject_status", table_name="auth_policies")
    op.drop_table("auth_policies")

    op.drop_index("ix_auth_sessions_person_id_expires_at", table_name="auth_sessions")
    op.drop_table("auth_sessions")

    op.drop_index("ix_auth_challenges_identity_id_status", table_name="auth_challenges")
    op.drop_index("ix_auth_challenges_person_id_status", table_name="auth_challenges")
    op.drop_table("auth_challenges")

    op.drop_index("ix_auth_factors_identity_id_status", table_name="auth_factors")
    op.drop_index("ix_auth_factors_person_id_status", table_name="auth_factors")
    op.drop_table("auth_factors")

    op.drop_index("ix_auth_identities_type_normalized_status", table_name="auth_identities")
    op.drop_index("ix_auth_identities_person_id_status", table_name="auth_identities")
    op.drop_table("auth_identities")
