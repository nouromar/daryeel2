"""pharmacy order assignments

Revision ID: 0009
Revises: 0008
Create Date: 2026-04-26

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "pharmacy_order_assignments",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "request_id",
            sa.Integer(),
            sa.ForeignKey("service_requests.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "pharmacy_id",
            sa.Uuid(),
            sa.ForeignKey("pharmacies.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column("assignment_kind", sa.String(length=64), nullable=False),
        sa.Column("assigned_person_id", sa.Uuid(), nullable=True),
        sa.Column("assigned_role_code", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("attempt_no", sa.Integer(), nullable=False),
        sa.Column("reason_code", sa.String(length=64), nullable=True),
        sa.Column(
            "started_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
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
        "ix_pharmacy_order_assignments_request_kind_status",
        "pharmacy_order_assignments",
        ["request_id", "assignment_kind", "status"],
    )
    op.create_index(
        "ix_pharmacy_order_assignments_pharmacy_id_status",
        "pharmacy_order_assignments",
        ["pharmacy_id", "status"],
    )
    op.create_index(
        "ix_pharmacy_order_assignments_assigned_person_id_status",
        "pharmacy_order_assignments",
        ["assigned_person_id", "status"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_pharmacy_order_assignments_assigned_person_id_status",
        table_name="pharmacy_order_assignments",
    )
    op.drop_index(
        "ix_pharmacy_order_assignments_pharmacy_id_status",
        table_name="pharmacy_order_assignments",
    )
    op.drop_index(
        "ix_pharmacy_order_assignments_request_kind_status",
        table_name="pharmacy_order_assignments",
    )
    op.drop_table("pharmacy_order_assignments")
