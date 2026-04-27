"""permissions and role permissions

Revision ID: 0015
Revises: 0014
Create Date: 2026-04-27

"""

from __future__ import annotations

import uuid

from alembic import op
import sqlalchemy as sa

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None

_SYSTEM_ROLES = (
    {
        "id": uuid.UUID("018f2f26-0000-7000-8000-000000000001"),
        "code": "admin",
        "role_group": "staff",
        "name": "Admin",
        "description": "Administrative staff with broad pharmacy fulfillment permissions.",
        "is_system": True,
    },
    {
        "id": uuid.UUID("018f2f26-0000-7000-8000-000000000002"),
        "code": "dispatcher",
        "role_group": "staff",
        "name": "Dispatcher",
        "description": "Operations staff who manage pharmacy order routing and dispatch.",
        "is_system": True,
    },
    {
        "id": uuid.UUID("018f2f26-0000-7000-8000-000000000003"),
        "code": "specialist",
        "role_group": "staff",
        "name": "Specialist",
        "description": "Specialist staff who can resolve pharmacy order issues.",
        "is_system": True,
    },
    {
        "id": uuid.UUID("018f2f26-0000-7000-8000-000000000004"),
        "code": "pharmacist",
        "role_group": "provider",
        "name": "Pharmacist",
        "description": "Licensed pharmacy provider who can review and fulfill orders.",
        "is_system": True,
    },
    {
        "id": uuid.UUID("018f2f26-0000-7000-8000-000000000005"),
        "code": "branch_staff",
        "role_group": "provider",
        "name": "Branch Staff",
        "description": "Branch team member who can manage pharmacy fulfillment operations.",
        "is_system": True,
    },
    {
        "id": uuid.UUID("018f2f26-0000-7000-8000-000000000006"),
        "code": "delivery_rider",
        "role_group": "provider",
        "name": "Delivery Rider",
        "description": "Delivery provider who completes pharmacy deliveries.",
        "is_system": True,
    },
    {
        "id": uuid.UUID("018f2f26-0000-7000-8000-000000000007"),
        "code": "driver",
        "role_group": "provider",
        "name": "Driver",
        "description": "Driver who can complete pharmacy deliveries.",
        "is_system": True,
    },
)

_SYSTEM_PERMISSIONS = (
    {
        "id": uuid.UUID("018f2f26-0000-7000-8000-000000000101"),
        "code": "pharmacy.manage_orders",
        "name": "Manage pharmacy orders",
        "description": "Assign, review, reroute, confirm, and dispatch pharmacy fulfillment orders.",
        "is_system": True,
    },
    {
        "id": uuid.UUID("018f2f26-0000-7000-8000-000000000102"),
        "code": "pharmacy.complete_delivery",
        "name": "Complete pharmacy delivery",
        "description": "Mark pharmacy deliveries completed or failed.",
        "is_system": True,
    },
)

_ROLE_PERMISSION_CODES = {
    "admin": {"pharmacy.manage_orders", "pharmacy.complete_delivery"},
    "dispatcher": {"pharmacy.manage_orders"},
    "specialist": {"pharmacy.manage_orders"},
    "pharmacist": {"pharmacy.manage_orders"},
    "branch_staff": {"pharmacy.manage_orders"},
    "delivery_rider": {"pharmacy.complete_delivery"},
    "driver": {"pharmacy.complete_delivery"},
}


def _roles_table() -> sa.Table:
    return sa.table(
        "roles",
        sa.column("id", sa.Uuid()),
        sa.column("code", sa.String()),
        sa.column("role_group", sa.String()),
        sa.column("name", sa.String()),
        sa.column("description", sa.Text()),
        sa.column("is_system", sa.Boolean()),
    )


def _permissions_table() -> sa.Table:
    return sa.table(
        "permissions",
        sa.column("id", sa.Uuid()),
        sa.column("code", sa.String()),
        sa.column("name", sa.String()),
        sa.column("description", sa.Text()),
        sa.column("is_system", sa.Boolean()),
    )


def _role_permissions_table() -> sa.Table:
    return sa.table(
        "role_permissions",
        sa.column("role_id", sa.Uuid()),
        sa.column("permission_id", sa.Uuid()),
    )


def _seed_roles_and_permissions() -> None:
    bind = op.get_bind()
    roles_table = _roles_table()
    permissions_table = _permissions_table()
    role_permissions_table = _role_permissions_table()

    existing_role_codes = set(
        bind.execute(
            sa.select(roles_table.c.code).where(
                roles_table.c.code.in_([row["code"] for row in _SYSTEM_ROLES])
            )
        ).scalars()
    )
    missing_roles = [row for row in _SYSTEM_ROLES if row["code"] not in existing_role_codes]
    if missing_roles:
        op.bulk_insert(roles_table, missing_roles)

    existing_permission_codes = set(
        bind.execute(
            sa.select(permissions_table.c.code).where(
                permissions_table.c.code.in_([row["code"] for row in _SYSTEM_PERMISSIONS])
            )
        ).scalars()
    )
    missing_permissions = [
        row for row in _SYSTEM_PERMISSIONS if row["code"] not in existing_permission_codes
    ]
    if missing_permissions:
        op.bulk_insert(permissions_table, missing_permissions)

    role_id_by_code = {
        row.code: row.id
        for row in bind.execute(
            sa.select(roles_table.c.code, roles_table.c.id).where(
                roles_table.c.code.in_([row["code"] for row in _SYSTEM_ROLES])
            )
        )
    }
    permission_id_by_code = {
        row.code: row.id
        for row in bind.execute(
            sa.select(permissions_table.c.code, permissions_table.c.id).where(
                permissions_table.c.code.in_([row["code"] for row in _SYSTEM_PERMISSIONS])
            )
        )
    }
    existing_pairs = {
        (row.role_id, row.permission_id)
        for row in bind.execute(
            sa.select(role_permissions_table.c.role_id, role_permissions_table.c.permission_id)
        )
    }

    rows_to_insert: list[dict[str, object]] = []
    for role_code, permission_codes in _ROLE_PERMISSION_CODES.items():
        role_id = role_id_by_code.get(role_code)
        if role_id is None:
            continue
        for permission_code in permission_codes:
            permission_id = permission_id_by_code.get(permission_code)
            if permission_id is None or (role_id, permission_id) in existing_pairs:
                continue
            rows_to_insert.append({"role_id": role_id, "permission_id": permission_id})

    if rows_to_insert:
        op.bulk_insert(role_permissions_table, rows_to_insert)


def upgrade() -> None:
    op.create_table(
        "permissions",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column("code", sa.String(length=128), nullable=False),
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
        sa.UniqueConstraint("code", name="uq_permissions_code"),
    )
    op.create_table(
        "role_permissions",
        sa.Column(
            "role_id",
            sa.Uuid(),
            sa.ForeignKey("roles.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column(
            "permission_id",
            sa.Uuid(),
            sa.ForeignKey("permissions.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )
    _seed_roles_and_permissions()


def downgrade() -> None:
    op.drop_table("role_permissions")
    op.drop_table("permissions")
