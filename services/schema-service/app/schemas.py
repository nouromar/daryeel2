from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str = "ok"
    service: str = "runtime-service"


class ActionDefinition(BaseModel):
    type: str
    route: str | None = None
    formId: str | None = None


class RefNode(BaseModel):
    ref: str


SchemaNode = "ComponentNode | RefNode"


class ComponentNode(BaseModel):
    type: str
    props: dict[str, Any] = Field(default_factory=dict)
    slots: dict[str, list[ComponentNode | RefNode]] = Field(default_factory=dict)
    actions: dict[str, str] = Field(default_factory=dict)
    bind: str | None = None


class ScreenSchema(BaseModel):
    schemaVersion: str
    id: str
    documentType: str = "screen"
    product: str
    service: str | None = None
    themeId: str
    themeMode: str | None = None
    root: ComponentNode
    actions: dict[str, ActionDefinition] = Field(default_factory=dict)


class FragmentSchema(BaseModel):
    schemaVersion: str
    id: str
    documentType: str = "fragment"
    node: ComponentNode


class BootstrapResponse(BaseModel):
    product: str
    screens: list[str]


class ProductBootstrapResponse(BaseModel):
    bootstrapVersion: int = 1
    product: str
    initialScreenId: str
    defaultThemeId: str
    defaultThemeMode: str = "light"

    configSchemaVersion: int = 1
    configSnapshotId: str
    configTtlSeconds: int = 3600

    schemaServiceBaseUrl: str | None = None
    themeServiceBaseUrl: str | None = None
    configServiceBaseUrl: str | None = None
    telemetryIngestUrl: str | None = None


class ConfigSnapshotResponse(BaseModel):
    schemaVersion: int = 1
    snapshotId: str
    createdAt: str | None = None

    # Keep v1 flexible: clients should ignore unknown keys.
    flags: dict[str, Any] = Field(default_factory=dict)
    telemetry: dict[str, Any] = Field(default_factory=dict)
    runtime: dict[str, Any] = Field(default_factory=dict)
    serviceCatalog: dict[str, Any] = Field(default_factory=dict)


class ThemeCatalogResponse(BaseModel):
    themes: list[str]


class ThemeDocument(BaseModel):
    # Theme JSON is treated as a contract document; keep it flexible for now.
    themeId: str
    themeMode: str
    inherits: list[str]
    tokens: dict[str, Any]
