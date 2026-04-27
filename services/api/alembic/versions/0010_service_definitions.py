"""service definitions

Revision ID: 0010
Revises: 0009
Create Date: 2026-04-27

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


_SERVICE_DEFINITIONS = (
    {
        "id": "ambulance",
        "title": "Ambulance",
        "subtitle": "Emergency transport",
        "icon": "ambulance",
        "status": "active",
    },
    {
        "id": "home_visit",
        "title": "Home visit",
        "subtitle": "Doctor comes to you",
        "icon": "house",
        "status": "active",
    },
    {
        "id": "pharmacy",
        "title": "Pharmacy",
        "subtitle": "Order medicine",
        "icon": "pill",
        "status": "active",
    },
)


def upgrade() -> None:
    op.create_table(
        "service_definitions",
        sa.Column("id", sa.String(length=64), primary_key=True, nullable=False),
        sa.Column("title", sa.String(length=128), nullable=False),
        sa.Column("subtitle", sa.String(length=200), nullable=True),
        sa.Column("icon", sa.String(length=64), nullable=True),
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

    service_definitions = sa.table(
        "service_definitions",
        sa.column("id", sa.String(length=64)),
        sa.column("title", sa.String(length=128)),
        sa.column("subtitle", sa.String(length=200)),
        sa.column("icon", sa.String(length=64)),
        sa.column("status", sa.String(length=32)),
    )
    op.bulk_insert(service_definitions, list(_SERVICE_DEFINITIONS))


def downgrade() -> None:
    op.drop_table("service_definitions")
