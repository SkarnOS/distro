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
import semver

from base_types import *

containers = {
    "registry.k8s.io/kube-apiserver": SpecialVersion.KUBERNETES,
    "registry.k8s.io/kube-controller-manager": SpecialVersion.KUBERNETES,
    "registry.k8s.io/kube-scheduler": SpecialVersion.KUBERNETES,
    "registry.k8s.io/pause": SpecialVersion.PAUSE_VERSION,
    "quay.io/cilium/cilium": "v1.18.2",
    "quay.io/cilium/operator-generic": "v1.18.2",
    "registry.k8s.io/coredns/coredns": SpecialVersion.COREDNS_VERSION,
    "registry.k8s.io/etcd": SpecialVersion.DEFAULT_ETCD_VERSION
}

sem: asyncio.Semaphore | NoopSemaphore = NoopSemaphore()

async def prefetch_kubernetes_version(tmpdir: str, release: Release):
    async with sem:
        print(f"fetching {release.latest.name}")

        process = await asyncio.create_subprocess_exec(
            "nix", "store", "prefetch-file",
            "--hash-type", "sha256",
            "--json",
            "--unpack",
            f"https://github.com/kubernetes/kubernetes/archive/refs/tags/v{release.latest.name}.tar.gz",
            stdout = asyncio.subprocess.PIPE,
            stderr = asyncio.subprocess.PIPE,
            env = os.environ | { "TMPDIR": tmpdir }
        )
        stdout, stderr = await process.communicate()

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

async def resolve_special_version(tmpdir: str, kubernetes_version: str, image: str, image_version: SpecialVersion):
    if image_version == SpecialVersion.KUBERNETES:
        return f"v{kubernetes_version}"

    async with sem:
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
            stderr = asyncio.subprocess.PIPE,
            env = os.environ | { "TMPDIR": tmpdir }
        )

        stdout, stderr = await process.communicate()

    if process.returncode == 0:
            pattern: str
            ensure_v_prefix: bool = False
            constants_path = stdout.strip()

            match image_version:
                case SpecialVersion.COREDNS_VERSION:
                    ensure_v_prefix = True
                    pattern = '''(?<=CoreDNSVersion = ")([^"]+)(?=")'''
                    constants_path += b"/cmd/kubeadm/app/constants/constants.go"
                case SpecialVersion.DEFAULT_ETCD_VERSION:
                    pattern = '''(?<=MinExternalEtcdVersion = ")([^"]+)(?=")'''
                    constants_path += b"/cmd/kubeadm/app/constants/constants.go"
                case SpecialVersion.PAUSE_VERSION:
                    pattern = '''(?<=PauseVersion = ")([^"]+)(?=")'''
                    kubernetes_version_semver = semver.Version.parse(kubernetes_version)
                    if kubernetes_version_semver < semver.Version.parse("1.21.0") \
                       and kubernetes_version_semver > semver.Version.parse("1.18.0"):
                        constants_path += b"/cmd/kubeadm/app/constants/constants_unix.go"
                    else:
                        constants_path += b"/cmd/kubeadm/app/constants/constants.go"

            with open(constants_path, "r") as constants_file:
                constants = constants_file.read()
                match = re.search(pattern, constants)
                if match:
                    version = match.group(0)
                    if ensure_v_prefix and version[0] != 'v':
                        version = f"v{version}"

                    return version
                else:
                    print(constants)
                    print(constants_path)
                    raise CouldNotResolveImageVersion(kubernetes_version = kubernetes_version, image = image)

    raise CouldNotResolveImageVersion(kubernetes_version = kubernetes_version, image = image, stderr = stderr)




async def sync_kubernetes_versions(concurrency_limit: int | None = None):
    global sem

    if concurrency_limit is not None:
        sem = asyncio.Semaphore(concurrency_limit)

    response = requests.get('https://endoflife.date/api/v1/products/kubernetes/')
    data = response.json()
    toplevel = TopLevel.model_validate(data)

    tmpdir = os.getcwd() + "/tmpdir"
    try:
        if not os.path.exists(tmpdir):
            os.mkdir(tmpdir)

        sources_list: list[dict[str, Source | str]] = await asyncio.gather(*map(lambda release: prefetch_kubernetes_version(tmpdir, release), toplevel.result.releases))
        sources: dict[str, Source | str] = reduce(operator.or_, sources_list, {})

        for name, value in list(sources.items()):
            if isinstance(value, str):
                version = value
            else:
                version = name
            if semver.Version.parse(version) < semver.Version.parse("1.18.0"):
                del sources[name]

        with open("packages/sources.json", "wb") as sources_file:
            json = TypeAdapter(Sources).dump_json(sources, indent = 4)
            sources_file.write(json)

        for version in sources.keys():
            if isinstance(sources[version], str):
                continue

            for name, container_version in containers.items():
                if isinstance(container_version, SpecialVersion):
                    container_version = await resolve_special_version(tmpdir, version, name, container_version)

                print (f"resolved {name} to {container_version} for kubernetes {version}")
                sources[version].containers[name] = container_version

        with open("packages/sources.json", "wb") as sources_file:
            json = TypeAdapter(Sources).dump_json(sources, indent = 4)
            sources_file.write(json)

    finally:
        shutil.rmtree(tmpdir)
