"""pharmacy order detail and item tables

Revision ID: 0008
Revises: 0007
Create Date: 2026-04-26

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "pharmacy_order_details",
        sa.Column(
            "request_id",
            sa.Integer(),
            sa.ForeignKey("service_requests.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column(
            "selected_pharmacy_id",
            sa.Uuid(),
            sa.ForeignKey("pharmacies.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("currency_code", sa.String(length=3), nullable=False),
        sa.Column("subtotal_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("discount_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("fee_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("tax_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("total_amount", sa.Numeric(12, 2), nullable=False),
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
        "ix_pharmacy_order_details_selected_pharmacy_id",
        "pharmacy_order_details",
        ["selected_pharmacy_id"],
    )

    op.create_table(
        "pharmacy_order_items",
        sa.Column("id", sa.Uuid(), primary_key=True, nullable=False),
        sa.Column(
            "request_id",
            sa.Integer(),
            sa.ForeignKey("service_requests.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "product_id",
            sa.Uuid(),
            sa.ForeignKey("products.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("product_name", sa.String(length=200), nullable=False),
        sa.Column("form", sa.String(length=64), nullable=True),
        sa.Column("strength", sa.String(length=64), nullable=True),
        sa.Column("rx_required", sa.Boolean(), nullable=False),
        sa.Column("seller_sku", sa.String(length=64), nullable=True),
        sa.Column("unit_price_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("line_subtotal_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("line_discount_amount", sa.Numeric(12, 2), nullable=True),
        sa.Column("line_tax_amount", sa.Numeric(12, 2), nullable=True),
        sa.Column("line_total_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_pharmacy_order_items_request_id",
        "pharmacy_order_items",
        ["request_id"],
    )
    op.create_index(
        "ix_pharmacy_order_items_product_id",
        "pharmacy_order_items",
        ["product_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_pharmacy_order_items_product_id",
        table_name="pharmacy_order_items",
    )
    op.drop_index(
        "ix_pharmacy_order_items_request_id",
        table_name="pharmacy_order_items",
    )
    op.drop_table("pharmacy_order_items")
    op.drop_index(
        "ix_pharmacy_order_details_selected_pharmacy_id",
        table_name="pharmacy_order_details",
    )
    op.drop_table("pharmacy_order_details")
