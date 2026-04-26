"""pharmacy catalog tables

Revision ID: 0007
Revises: 0006
Create Date: 2026-04-26

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "organizations",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("address_text", sa.String(length=255), nullable=True),
        sa.Column("country_code", sa.String(length=2), nullable=True),
        sa.Column("region_code", sa.String(length=64), nullable=True),
        sa.Column("city_name", sa.String(length=128), nullable=True),
        sa.Column("lat", sa.Numeric(10, 7), nullable=True),
        sa.Column("lng", sa.Numeric(10, 7), nullable=True),
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
        "products",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column("sku", sa.String(length=64), nullable=True),
        sa.Column("barcode", sa.String(length=64), nullable=True),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("generic_name", sa.String(length=200), nullable=True),
        sa.Column("brand_name", sa.String(length=200), nullable=True),
        sa.Column("form", sa.String(length=64), nullable=True),
        sa.Column("strength", sa.String(length=64), nullable=True),
        sa.Column("rx_required", sa.Boolean(), nullable=False),
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

    op.create_table(
        "product_categories",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=128), nullable=False),
        sa.Column(
            "parent_id",
            sa.Uuid(),
            sa.ForeignKey("product_categories.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=True),
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
        sa.UniqueConstraint("code", name="uq_product_categories_code"),
    )

    op.create_table(
        "pharmacies",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "organization_id",
            sa.Uuid(),
            sa.ForeignKey("organizations.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("branch_code", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("address_text", sa.String(length=255), nullable=True),
        sa.Column("country_code", sa.String(length=2), nullable=True),
        sa.Column("region_code", sa.String(length=64), nullable=True),
        sa.Column("city_name", sa.String(length=128), nullable=True),
        sa.Column("zone_code", sa.String(length=64), nullable=True),
        sa.Column("lat", sa.Numeric(10, 7), nullable=True),
        sa.Column("lng", sa.Numeric(10, 7), nullable=True),
        sa.Column("place_id", sa.String(length=255), nullable=True),
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
        "ix_pharmacies_organization_id_status",
        "pharmacies",
        ["organization_id", "status"],
    )

    op.create_table(
        "product_images",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "product_id",
            sa.Uuid(),
            sa.ForeignKey("products.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("storage_key", sa.String(length=512), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("is_primary", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )

    op.create_table(
        "product_category_assignments",
        sa.Column(
            "product_id",
            sa.Uuid(),
            sa.ForeignKey("products.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column(
            "category_id",
            sa.Uuid(),
            sa.ForeignKey("product_categories.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column("sort_order", sa.Integer(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )

    op.create_table(
        "pharmacy_products",
        sa.Column(
            "pharmacy_id",
            sa.Uuid(),
            sa.ForeignKey("pharmacies.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column(
            "product_id",
            sa.Uuid(),
            sa.ForeignKey("products.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column("seller_sku", sa.String(length=64), nullable=True),
        sa.Column("price_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency_code", sa.String(length=3), nullable=False),
        sa.Column("stock_status", sa.String(length=32), nullable=False),
        sa.Column("available_quantity", sa.Integer(), nullable=True),
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
        "ix_pharmacy_products_product_id_status",
        "pharmacy_products",
        ["product_id", "status"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_pharmacy_products_product_id_status",
        table_name="pharmacy_products",
    )
    op.drop_table("pharmacy_products")
    op.drop_table("product_category_assignments")
    op.drop_table("product_images")
    op.drop_index(
        "ix_pharmacies_organization_id_status",
        table_name="pharmacies",
    )
    op.drop_table("pharmacies")
    op.drop_table("product_categories")
    op.drop_table("products")
    op.drop_table("organizations")
