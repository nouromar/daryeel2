"""people and profile tables

Revision ID: 0011
Revises: 0010
Create Date: 2026-04-27

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

from app.ids import new_uuid7

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "people",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column("primary_person_type", sa.String(length=32), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("display_name", sa.String(length=200), nullable=True),
        sa.Column("first_name", sa.String(length=100), nullable=True),
        sa.Column("last_name", sa.String(length=100), nullable=True),
        sa.Column("preferred_language", sa.String(length=16), nullable=True),
        sa.Column("timezone", sa.String(length=64), nullable=True),
        sa.Column("country_code", sa.String(length=2), nullable=True),
        sa.Column("phone_e164", sa.String(length=32), nullable=True),
        sa.Column("email", sa.String(length=320), nullable=True),
        sa.Column("date_of_birth", sa.Date(), nullable=True),
        sa.Column("avatar_url", sa.String(length=500), nullable=True),
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
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.create_table(
        "customer_profiles",
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column("customer_number", sa.String(length=64), nullable=True, unique=True),
        sa.Column("marketing_consent", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("support_tier", sa.String(length=32), nullable=True),
        sa.Column("default_country_code", sa.String(length=2), nullable=True),
        sa.Column("notes_internal", sa.Text(), nullable=True),
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

    op.create_table(
        "provider_profiles",
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column("provider_kind", sa.String(length=32), nullable=False),
        sa.Column("employment_type", sa.String(length=32), nullable=True),
        sa.Column("license_number", sa.String(length=128), nullable=True),
        sa.Column("license_country_code", sa.String(length=2), nullable=True),
        sa.Column("license_expires_at", sa.Date(), nullable=True),
        sa.Column("verification_status", sa.String(length=32), nullable=False),
        sa.Column("availability_status", sa.String(length=32), nullable=False),
        sa.Column("home_country_code", sa.String(length=2), nullable=True),
        sa.Column("notes_internal", sa.Text(), nullable=True),
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

    op.create_table(
        "staff_profiles",
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column("staff_code", sa.String(length=64), nullable=True, unique=True),
        sa.Column("employment_type", sa.String(length=32), nullable=True),
        sa.Column("department", sa.String(length=64), nullable=True),
        sa.Column("vpn_required", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("mfa_required", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("break_glass_eligible", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("notes_internal", sa.Text(), nullable=True),
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

    bind = op.get_bind()
    if bind.dialect.name == "sqlite":
        with op.batch_alter_table("users", recreate="always") as batch_op:
            batch_op.add_column(sa.Column("person_id", sa.Uuid(), nullable=True))
            batch_op.create_foreign_key(
                "fk_users_person_id_people",
                "people",
                ["person_id"],
                ["id"],
                ondelete="RESTRICT",
            )
            batch_op.create_unique_constraint("uq_users_person_id", ["person_id"])
    else:
        op.add_column("users", sa.Column("person_id", sa.Uuid(), nullable=True))
        op.create_foreign_key(
            "fk_users_person_id_people",
            "users",
            "people",
            ["person_id"],
            ["id"],
            ondelete="RESTRICT",
        )
        op.create_unique_constraint("uq_users_person_id", "users", ["person_id"])

    metadata = sa.MetaData()
    people = sa.Table("people", metadata, autoload_with=bind)
    customer_profiles = sa.Table("customer_profiles", metadata, autoload_with=bind)
    users = sa.Table("users", metadata, autoload_with=bind)

    rows = list(
        bind.execute(
            sa.select(users.c.id, users.c.phone, users.c.created_at).where(users.c.person_id.is_(None))
        ).mappings()
    )
    for row in rows:
        person_id = str(new_uuid7())
        created_at = row["created_at"]
        bind.execute(
            people.insert().values(
                id=person_id,
                primary_person_type="customer",
                status="active",
                phone_e164=row["phone"],
                created_at=created_at,
                updated_at=created_at,
            )
        )
        bind.execute(
            customer_profiles.insert().values(
                person_id=person_id,
                marketing_consent=False,
                created_at=created_at,
                updated_at=created_at,
            )
        )
        bind.execute(
            users.update().where(users.c.id == row["id"]).values(person_id=person_id)
        )


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "sqlite":
        with op.batch_alter_table("users", recreate="always") as batch_op:
            batch_op.drop_constraint("uq_users_person_id", type_="unique")
            batch_op.drop_constraint("fk_users_person_id_people", type_="foreignkey")
            batch_op.drop_column("person_id")
    else:
        op.drop_constraint("uq_users_person_id", "users", type_="unique")
        op.drop_constraint("fk_users_person_id_people", "users", type_="foreignkey")
        op.drop_column("users", "person_id")

    op.drop_table("staff_profiles")
    op.drop_table("provider_profiles")
    op.drop_table("customer_profiles")
    op.drop_table("people")
