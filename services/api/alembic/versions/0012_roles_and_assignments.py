"""roles and person role assignments

Revision ID: 0012
Revises: 0011
Create Date: 2026-04-27

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "roles",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("role_group", sa.String(length=32), nullable=False),
        sa.Column("name", sa.String(length=128), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_system", sa.Boolean(), nullable=False, server_default=sa.text("false")),
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
        sa.UniqueConstraint("code", name="uq_roles_code"),
    )

    op.create_table(
        "person_role_assignments",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "role_id",
            sa.Uuid(),
            sa.ForeignKey("roles.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "organization_id",
            sa.Uuid(),
            sa.ForeignKey("organizations.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column(
            "service_id",
            sa.String(length=64),
            sa.ForeignKey("service_definitions.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column(
            "assigned_by_person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="RESTRICT"),
            nullable=True,
        ),
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
        "ix_person_role_assignments_person_id_status",
        "person_role_assignments",
        ["person_id", "status"],
    )
    op.create_index(
        "ix_person_role_assignments_role_id_status",
        "person_role_assignments",
        ["role_id", "status"],
    )
    op.create_index(
        "ix_person_role_assignments_organization_id_status",
        "person_role_assignments",
        ["organization_id", "status"],
    )
    op.create_index(
        "ix_person_role_assignments_service_id_status",
        "person_role_assignments",
        ["service_id", "status"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_person_role_assignments_service_id_status",
        table_name="person_role_assignments",
    )
    op.drop_index(
        "ix_person_role_assignments_organization_id_status",
        table_name="person_role_assignments",
    )
    op.drop_index(
        "ix_person_role_assignments_role_id_status",
        table_name="person_role_assignments",
    )
    op.drop_index(
        "ix_person_role_assignments_person_id_status",
        table_name="person_role_assignments",
    )
    op.drop_table("person_role_assignments")
    op.drop_table("roles")
