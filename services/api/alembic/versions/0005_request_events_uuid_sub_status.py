"""request events uuid and request sub status

Revision ID: 0005
Revises: 0004
Create Date: 2026-04-26

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

from app.ids import new_uuid7

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def _map_legacy_event_type(value: str) -> str:
    return {
        "created": "request_created",
        "status_changed": "request_status_changed",
        "prescription_requested": "request_status_changed",
        "prescription_uploaded": "attachment_added",
        "price_change_proposed": "customer_confirmation_requested",
        "price_change_confirmed": "customer_confirmation_resolved",
        "price_change_rejected": "customer_confirmation_resolved",
        "substitution_requested": "customer_confirmation_requested",
        "substitution_confirmed": "customer_confirmation_resolved",
        "substitution_rejected": "customer_confirmation_resolved",
    }.get(value, value)


def upgrade() -> None:
    op.add_column(
        "service_requests",
        sa.Column("sub_status", sa.String(length=64), nullable=True),
    )

    op.create_table(
        "request_events_new",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "request_id",
            sa.Integer(),
            sa.ForeignKey("service_requests.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("type", sa.String(length=64), nullable=False),
        sa.Column("from_status", sa.String(length=64), nullable=True),
        sa.Column("to_status", sa.String(length=64), nullable=True),
        sa.Column("actor_type", sa.String(length=32), nullable=False),
        sa.Column("actor_id", sa.Integer(), nullable=True),
        sa.Column("related_entity_type", sa.String(length=64), nullable=True),
        sa.Column("related_entity_id", sa.String(length=128), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )

    bind = op.get_bind()
    metadata = sa.MetaData()
    old_events = sa.Table("request_events", metadata, autoload_with=bind)
    new_events = sa.Table("request_events_new", metadata, autoload_with=bind)

    rows = list(
        bind.execute(
            sa.select(old_events).order_by(old_events.c.created_at.asc(), old_events.c.id.asc())
        ).mappings()
    )
    if rows:
        bind.execute(
            new_events.insert(),
            [
                {
                    "id": new_uuid7(),
                    "request_id": row["request_id"],
                    "type": _map_legacy_event_type(str(row["type"])),
                    "from_status": row["from_status"],
                    "to_status": row["to_status"],
                    "actor_type": row["actor_type"],
                    "actor_id": row["actor_id"],
                    "related_entity_type": None,
                    "related_entity_id": None,
                    "metadata_json": row["metadata_json"],
                    "created_at": row["created_at"],
                }
                for row in rows
            ],
        )

    op.drop_table("request_events")
    op.rename_table("request_events_new", "request_events")


def downgrade() -> None:
    op.create_table(
        "request_events_old",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column(
            "request_id",
            sa.Integer(),
            sa.ForeignKey("service_requests.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("type", sa.String(length=64), nullable=False),
        sa.Column("from_status", sa.String(length=64), nullable=True),
        sa.Column("to_status", sa.String(length=64), nullable=True),
        sa.Column("actor_type", sa.String(length=32), nullable=False),
        sa.Column("actor_id", sa.Integer(), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )

    bind = op.get_bind()
    metadata = sa.MetaData()
    current_events = sa.Table("request_events", metadata, autoload_with=bind)
    downgraded_events = sa.Table("request_events_old", metadata, autoload_with=bind)

    rows = list(
        bind.execute(
            sa.select(current_events).order_by(current_events.c.created_at.asc(), current_events.c.id.asc())
        ).mappings()
    )
    if rows:
        bind.execute(
            downgraded_events.insert(),
            [
                {
                    "id": index,
                    "request_id": row["request_id"],
                    "type": row["type"],
                    "from_status": row["from_status"],
                    "to_status": row["to_status"],
                    "actor_type": row["actor_type"],
                    "actor_id": row["actor_id"],
                    "metadata_json": row["metadata_json"],
                    "created_at": row["created_at"],
                }
                for index, row in enumerate(rows, start=1)
            ],
        )

    op.drop_table("request_events")
    op.rename_table("request_events_old", "request_events")
    op.drop_column("service_requests", "sub_status")
