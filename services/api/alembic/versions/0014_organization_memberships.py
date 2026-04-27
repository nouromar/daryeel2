"""organization memberships

Revision ID: 0014
Revises: 0013
Create Date: 2026-04-27

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "organization_memberships",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "organization_id",
            sa.Uuid(),
            sa.ForeignKey("organizations.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("membership_type", sa.String(length=32), nullable=False),
        sa.Column("title", sa.String(length=128), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
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
        "ix_organization_memberships_person_id_status",
        "organization_memberships",
        ["person_id", "status"],
    )
    op.create_index(
        "ix_organization_memberships_organization_id_status",
        "organization_memberships",
        ["organization_id", "status"],
    )
    op.create_index(
        "ix_organization_memberships_person_org_type_status",
        "organization_memberships",
        ["person_id", "organization_id", "membership_type", "status"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_organization_memberships_person_org_type_status",
        table_name="organization_memberships",
    )
    op.drop_index(
        "ix_organization_memberships_organization_id_status",
        table_name="organization_memberships",
    )
    op.drop_index(
        "ix_organization_memberships_person_id_status",
        table_name="organization_memberships",
    )
    op.drop_table("organization_memberships")
