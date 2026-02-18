from dataclasses import dataclass
from datetime import datetime, date
from pydantic import BaseModel, TypeAdapter
from pathlib import Path
from functools import reduce
from async_lru import alru_cache
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
    "registry.k8s.io/kube-apiserver": [SpecialVersion.KUBERNETES],
    "registry.k8s.io/kube-controller-manager": [SpecialVersion.KUBERNETES],
    "registry.k8s.io/kube-scheduler": [SpecialVersion.KUBERNETES],
    "registry.k8s.io/pause": [SpecialVersion.PAUSE_VERSION],
    "quay.io/cilium/cilium": [SpecialVersion.CILIUM_VERSION],
    "quay.io/cilium/operator-generic": [SpecialVersion.CILIUM_VERSION],
    "registry.k8s.io/coredns/coredns": [
        SpecialVersion.COREDNS_VERSION,
        SpecialVersion.CILIUM_GREP
    ],
    "registry.k8s.io/etcd": [SpecialVersion.DEFAULT_ETCD_VERSION],
    "quay.io/cilium/network-perf": [SpecialVersion.CILIUM_GREP],
    "quay.io/cilium/alpine-curl": [SpecialVersion.CILIUM_GREP],
    "quay.io/cilium/test-connection-disruption": [SpecialVersion.CILIUM_GREP],
    "quay.io/cilium/json-mock": [SpecialVersion.CILIUM_GREP],
    "quay.io/frrouting/frr": [SpecialVersion.CILIUM_GREP],
    "docker.io/alpine/socat": [SpecialVersion.CILIUM_GREP]
}

sem: asyncio.Semaphore | NoopSemaphore = NoopSemaphore()

async def run_command(command: list[str], tmpdir: str) -> tuple[str, str]:
    process = await asyncio.create_subprocess_exec(
        *command,
        stdout = asyncio.subprocess.PIPE,
        stderr = asyncio.subprocess.PIPE,
        env = os.environ | { "TMPDIR": tmpdir }
    )

    stdout, stderr = await process.communicate()

    if process.returncode != 0:
        raise ProcessFailed(
            exit_code = process.returncode,
            stdout = stdout.decode('utf-8'),
            stderr = stderr.decode('utf-8'),
            command = command
        )

    return (stdout, stderr)

@alru_cache(maxsize=512)
async def get_cilium_image_version(tmpdir: str) -> str:
    try:
        async with sem:
            cilium_path, stderr = await run_command(
                command = [
                    "nix", "build", "--impure",
                    "--print-out-paths",
                    "--expr", f'''
                    let
                      flake = builtins.getFlake "git+file://{Path.cwd()}";
                    in
                      flake.legacyPackages.${{builtins.currentSystem}}.cilium-cli
                    '''
                ],
                tmpdir = tmpdir
            )


        async with sem:
            cilium_version, stderr = await run_command(
                command = [
                    cilium_path.strip().decode('utf-8') + "/bin/cilium", "version", "--client"
                ],
                tmpdir = tmpdir
            )

    except ProcessFailed as exception:
        raise CouldNotResolveImageVersion(
            kubernetes_version = kubernetes_version,
            image = image,
            exception = exception
        )

    cilium_version = cilium_version.strip().decode('utf-8')

    match = re.search(f'(?<=cilium image \\(default\\): v)(.+)', cilium_version)

    if match:
        return match.group(0)
    else:
        raise CouldNotResolveImageVersion(kubernetes_version = kubernetes_version, image = image)

async def prefetch_kubernetes_version(tmpdir: str, release: Release):
    try:
        async with sem:
            print(f"fetching {release.latest.name}")

            stdout, stderr = await run_command(
                command = [
                    "nix", "store", "prefetch-file",
                    "--hash-type", "sha256",
                    "--json",
                    "--unpack",
                    f"https://github.com/kubernetes/kubernetes/archive/refs/tags/v{release.latest.name}.tar.gz",
                ],
                tmpdir = tmpdir
            )
    except ProcessFailed as exception:
        raise CouldNotResolveImageVersion(
            kubernetes_version = kubernetes_version,
            image = image,
            exception = exception
        )


    output = NixStorePrefetchFileOutput.model_validate_json(stdout)

    print(f"fetched {release.latest.name} with hash {output.hash}")

    return {
        release.name: release.latest.name,
        release.latest.name: Source(
            version = release.latest.name,
            hash = output.hash,
            is_maintained = release.isMaintained,
            containers = {},
            cilium_image_version = await get_cilium_image_version(tmpdir)
        )
    }

@alru_cache(maxsize=512)
async def resolve_special_version(tmpdir: str, kubernetes_version: str, image: str, image_version: SpecialVersion):
    if image_version == SpecialVersion.KUBERNETES:
        return f"v{kubernetes_version}"

    if image_version == SpecialVersion.CILIUM_GREP:
        try:
            async with sem:
                cilium_src, stderr = await run_command(
                    command = [
                        "nix", "build", "--impure",
                        "--print-out-paths",
                        "--expr", f'''
                          let
                            flake = builtins.getFlake "git+file://{Path.cwd()}";
                          in
                            flake.legacyPackages.${{builtins.currentSystem}}.cilium-cli.src
                        '''
                    ],
                    tmpdir = tmpdir
                )
        except ProcessFailed as exception:
            raise CouldNotResolveImageVersion(
                kubernetes_version = kubernetes_version,
                image = image,
                exception = exception
            )

        with open(cilium_src.strip() + b"/vendor/github.com/cilium/cilium/cilium-cli/defaults/defaults.go", "r") as defaults_file:
            defaults = defaults_file.read()

            match = re.search(f'(?<={image}:)([^@]+)(?=@sha256:[^"]+)', defaults)

            if match:
                return match.group(0)
            else:
                raise CouldNotResolveImageVersion(kubernetes_version = kubernetes_version, image = image)
    if image_version == SpecialVersion.CILIUM_VERSION:
        return "v" + await get_cilium_image_version(tmpdir)
    else:
        try:
            async with sem:
                kubernetes_src, stderr = await run_command(
                    command = [
                        "nix", "build", "--impure",
                        "--print-out-paths",
                        "--expr", f'''
                          let
                            flake = builtins.getFlake "git+file://{Path.cwd()}";
                          in
                            flake.legacyPackages.${{builtins.currentSystem}}.kubernetes."{kubernetes_version.replace('.', '_')}".src
                        '''
                    ],
                    tmpdir = tmpdir
                )
        except ProcessFailed as exception:
            raise CouldNotResolveImageVersion(
                kubernetes_version = kubernetes_version,
                image = image,
                exception = exception
            )

        pattern: str
        ensure_v_prefix: bool = False
        constants_path = kubernetes_src.strip()

        match image_version:
            case SpecialVersion.COREDNS_VERSION:
                ensure_v_prefix = True
                pattern = '''(?<=CoreDNSVersion = ")([^"]+)(?=")'''
                constants_path += b"/cmd/kubeadm/app/constants/constants.go"
            case SpecialVersion.DEFAULT_ETCD_VERSION:
                pattern = '''(?<=DefaultEtcdVersion = ")([^"]+)(?=")'''
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
                raise CouldNotResolveImageVersion(kubernetes_version = kubernetes_version, image = image)




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

            for name, container_versions in containers.items():
                resolved_container_versions: list[str] = []
                for container_version in container_versions:
                    if isinstance(container_version, SpecialVersion):
                        resolved_container_versions += [await resolve_special_version(tmpdir, version, name, container_version)]
                    else:
                        resolved_container_versions += [container_version]
                container_versions = resolved_container_versions

                print (f"resolved {name} to {container_versions} for kubernetes {version}")
                sources[version].containers[name] = container_versions

        with open("packages/sources.json", "wb") as sources_file:
            json = TypeAdapter(Sources).dump_json(sources, indent = 4)
            sources_file.write(json)

    finally:
        shutil.rmtree(tmpdir)
