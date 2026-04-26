"""attachments and request attachments

Revision ID: 0006
Revises: 0005
Create Date: 2026-04-26

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "attachments",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column("storage_key", sa.String(length=512), nullable=False),
        sa.Column("filename", sa.String(length=255), nullable=True),
        sa.Column("content_type", sa.String(length=128), nullable=True),
        sa.Column("size_bytes", sa.Integer(), nullable=True),
        sa.Column("checksum_sha256", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )

    op.create_table(
        "request_attachments",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "request_id",
            sa.Integer(),
            sa.ForeignKey("service_requests.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "attachment_id",
            sa.Uuid(),
            sa.ForeignKey("attachments.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("attachment_type", sa.String(length=64), nullable=False),
        sa.Column("purpose", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("uploaded_by_actor_type", sa.String(length=32), nullable=False),
        sa.Column("uploaded_by_actor_id", sa.Integer(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("removed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
    )

    op.create_index(
        "ix_request_attachments_request_id_status",
        "request_attachments",
        ["request_id", "status"],
    )
    op.create_index(
        "ix_request_attachments_attachment_type",
        "request_attachments",
        ["attachment_type"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_request_attachments_attachment_type",
        table_name="request_attachments",
    )
    op.drop_index(
        "ix_request_attachments_request_id_status",
        table_name="request_attachments",
    )
    op.drop_table("request_attachments")
    op.drop_table("attachments")
