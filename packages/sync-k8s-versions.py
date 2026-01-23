from dataclasses import dataclass
from datetime import datetime, date
from pydantic import BaseModel, TypeAdapter
from functools import reduce
import requests
import pydantic
import subprocess
import os
import shutil
import asyncio
import operator

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

class Source(BaseModel):
    version: str
    hash: str
    is_maintained: bool

class NixStorePrefetchFileOutput(BaseModel):
    hash: str
    storePath: str

async def prefetch_kubernetes_version(tmpdir: str, release: Release):
    print(f"fetching {release.latest.name}")

    process = await asyncio.create_subprocess_exec(
        "nix", "store", "prefetch-file",
        "--hash-type", "sha256",
        "--json",
        "--unpack",
        f"https://github.com/kubernetes/kubernetes/archive/refs/tags/v{release.latest.name}.tar.gz",
        stdout = asyncio.subprocess.PIPE,
        stderr = asyncio.subprocess.DEVNULL,
        env = os.environ | { "TMPDIR": tmpdir }
    )
    stdout, _ = await process.communicate()

    if process.returncode == 0:
        output = NixStorePrefetchFileOutput.model_validate_json(stdout)

        print(f"fetched {release.latest.name} with hash {output.hash}")

        return {
            release.name: release.latest.name,
            release.latest.name: Source(
                version = release.latest.name,
                hash = output.hash,
                is_maintained = release.isMaintained
            )
        }

async def main():
    response = requests.get('https://endoflife.date/api/v1/products/kubernetes/')
    data = response.json()
    toplevel = TopLevel.model_validate(data)
    # print(toplevel)

    tmpdir = os.getcwd() + "/tmpdir"
    try:
        if not os.path.exists(tmpdir):
            os.mkdir(tmpdir)

        sources_list: list[dict[str, Source | str]] = await asyncio.gather(*map(lambda release: prefetch_kubernetes_version(tmpdir, release), toplevel.result.releases))
        sources: dict[str, Source | str] = reduce(operator.or_, sources_list, {})

        source_dict_adapter = TypeAdapter(dict[str, Source | str])

        with open("packages/sources.json", "wb") as sources_file:
            json = source_dict_adapter.dump_json(sources, indent = 4)
            sources_file.write(json)

    finally:
        shutil.rmtree(tmpdir)


asyncio.run(main())
