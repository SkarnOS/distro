from pydantic import BaseModel, TypeAdapter, Field
from datetime import date, datetime
from enum import Enum

class NoopSemaphore(BaseModel):
    async def __aenter__(self):
        pass

    async def __aexit__(self, exc_type, exc_value, traceback):
        pass

class Identifier(BaseModel):
    type: str
    id: str

class LatestRelease(BaseModel):
    name: str
    date: date
    link: str

class Release(BaseModel):
    name: str
    codename: None
    label: str
    releaseDate: date
    isLts: bool
    ltsFrom: None
    isEoas: bool
    eoasFrom: date | None
    isEol: bool
    eolFrom: str
    isMaintained: bool
    latest: LatestRelease
    custom: None

class Releases(BaseModel):
    name: str
    aliases: list[str]
    label: str
    category: str
    tags: list[str]
    versionCommand: str
    identifiers: list[Identifier]
    labels: dict[str, str | None]
    links: dict[str, str]
    releases: list[Release]

class TopLevel(BaseModel):
    schema_version: str
    generated_at: datetime
    last_modified: datetime
    result: Releases

class SpecialVersion(Enum):
    KUBERNETES = 1
    COREDNS_VERSION = 2
    DEFAULT_ETCD_VERSION = 3
    PAUSE_VERSION = 4
    CILIUM_GREP = 5

class Source(BaseModel):
    version: str
    hash: str
    is_maintained: bool
    containers: dict[str, list[str | SpecialVersion]]

class NixStorePrefetchFileOutput(BaseModel):
    hash: str
    storePath: str

class ImageSpec(BaseModel):
    hash: str | None
    digest: str | None

ImageVersions = dict[str, ImageSpec]
Images = dict[str, ImageVersions]
Sources = dict[str, Source | str]

class FlattenedImage(ImageSpec):
    name: str
    tag: str

    def to_image(self) -> ImageSpec:
        return ImageSpec(
            hash = self.hash,
            digest = self.digest
        )

class SkopeoImageInfo(BaseModel):
    digest: str = Field(alias = "Digest")

class CouldNotResolveImageVersion(Exception):
    kubernetes_version: str
    image: str
    stderr: str | None

    def __init__(self, kubernetes_version: str, image: str, stderr: str | None = None):
        super().__init__(f"Could not resolve version of image {image} for Kubernetes {kubernetes_version}: \n{stderr}")

        self.kubernetes_version = kubernetes_version
        self.image = image
        self.stderr = stderr
