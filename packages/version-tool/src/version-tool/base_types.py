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
    CILIUM_VERSION = 6
    FLANNEL_GREP = 7

class Source(BaseModel):
    version: str
    hash: str
    is_maintained: bool
    containers: dict[str, list[str | SpecialVersion]]
    cilium_image_version: str

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
    kubernetes_version: str | None
    image: str
    exception: Exception | None

    def __init__(self, image: str, kubernetes_version: str | None = None, exception: Exception | None = None):
        super().__init__(
            f"Could not resolve version of image {image}"
            + (f" for Kubernetes {kubernetes_version}" if kubernetes_version is not None else "")
            + (("\n" + str(exception)) if exception is not None else "")
        )

        self.kubernetes_version = kubernetes_version
        self.image = image
        self.exception = exception

class ProcessFailed(Exception):
    command: list[str]
    exit_code: int
    stdout: str
    stderr: str

    @classmethod
    def indent(cls, string: str) -> str:
        return "\n".join(map(lambda line: "    " + line, string.split("\n")))

    def __init__(self, command: list[str], exit_code: int, stdout: str, stderr: str):
        super().__init__("\n".join([
            f"Command exited with {exit_code}",
            "$ " + " ".join(command),
            "stdout: ",
            ProcessFailed.indent(stdout),
            "stderr: ",
            ProcessFailed.indent(stderr)
        ]))

        self.exit_code = exit_code
        self.stdout = stdout
        self.stderr = stderr
        self.command = command
