"""prescription_uploads

Revision ID: 0004
Revises: 0003
Create Date: 2026-04-06

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "prescription_uploads",
        sa.Column("id", sa.String(length=64), primary_key=True, nullable=False),
        sa.Column("service_id", sa.String(length=64), nullable=False),
        sa.Column(
            "customer_user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("filename", sa.String(length=255), nullable=True),
        sa.Column("content_type", sa.String(length=128), nullable=True),
        sa.Column("size_bytes", sa.Integer(), nullable=True),
        sa.Column("storage_path", sa.String(length=512), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )

    op.create_index(
        "ix_prescription_uploads_customer_user_id",
        "prescription_uploads",
        ["customer_user_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_prescription_uploads_customer_user_id",
        table_name="prescription_uploads",
    )
    op.drop_table("prescription_uploads")
