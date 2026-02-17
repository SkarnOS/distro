from dataclasses import dataclass
from datetime import datetime, date
from pydantic import BaseModel, TypeAdapter
from pathlib import Path
from functools import reduce
from enum import Enum
import requests
import re
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

class SpecialVersion(Enum):
    KUBERNETES = 1
    COREDNS_VERSION = 2
    DEFAULT_ETCD_VERSION = 3

class Source(BaseModel):
    version: str
    hash: str
    is_maintained: bool
    containers: dict[str, str | SpecialVersion]

class NixStorePrefetchFileOutput(BaseModel):
    hash: str
    storePath: str

containers = {
    "registry.k8s.io/kube-apiserver": SpecialVersion.KUBERNETES,
    "registry.k8s.io/kube-controller-manager": SpecialVersion.KUBERNETES,
    "registry.k8s.io/kube-scheduler": SpecialVersion.KUBERNETES,
    "registry.k8s.io/pause": SpecialVersion.KUBERNETES,
    "quay.io/cilium/cilium": "v1.18.2",
    "registry.k8s.io/coredns/coredns": SpecialVersion.COREDNS_VERSION,
    "registry.k8s.io/etcd": SpecialVersion.DEFAULT_ETCD_VERSION
}

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
                is_maintained = release.isMaintained,
                containers = {}
            )
        }

async def resolve_special_version(tmpdir: str, kubernetes_version: str, image_version: SpecialVersion):
    if image_version == SpecialVersion.KUBERNETES:
        return kubernetes_version

    process = await asyncio.create_subprocess_exec(
        "nix", "build", "--impure",
        "--print-out-paths",
        "--expr", f'''
          let
            flake = builtins.getFlake "{Path.cwd()}";
          in
            flake.legacyPackages.${{builtins.currentSystem}}.kubernetes."{kubernetes_version.replace('.', '_')}".src
        ''',
        stdout = asyncio.subprocess.PIPE,
        stderr = asyncio.subprocess.DEVNULL,
        env = os.environ | { "TMPDIR": tmpdir }
    )

    stdout, stderr = await process.communicate()

    if process.returncode == 0:
        with open(stdout.strip() + b"/cmd/kubeadm/app/constants/constants.go", "r") as constants_file:
            constants = constants_file.read()

            pattern: str

            match image_version:
                case SpecialVersion.COREDNS_VERSION:
                    pattern = '''(?<=CoreDNSVersion = ")([^"]+)(?=")'''
                case SpecialVersion.DEFAULT_ETCD_VERSION:
                    pattern = '''(?<=MinExternalEtcdVersion = ")([^"]+)(?=")'''

            match = re.search(pattern, constants)
            if match:
                return match.group(0)
    else:
        print (stderr)



async def main():
    response = requests.get('https://endoflife.date/api/v1/products/kubernetes/')
    data = response.json()
    toplevel = TopLevel.model_validate(data)

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

        for version in sources.keys():
            if isinstance(sources[version], str):
                continue

            for name, container_version in containers.items():
                if isinstance(container_version, SpecialVersion):
                    container_version = await resolve_special_version(tmpdir, version, container_version)

                    print (f"container_version: {container_version}")
                    sources[version].containers[name] = container_version
                else:
                    sources[version].containers[name] = container_version

        with open("packages/sources.json", "wb") as sources_file:
            json = source_dict_adapter.dump_json(sources, indent = 4)
            sources_file.write(json)

    finally:
        shutil.rmtree(tmpdir)


asyncio.run(main())
