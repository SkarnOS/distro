from dataclasses import dataclass
from datetime import datetime, date
from pydantic import BaseModel, TypeAdapter, Field
from functools import reduce
import requests
import pydantic
import subprocess
import os
import shutil
import asyncio
import operator
import re

from base_types import *

async def get_image_digest(tmpdir: str, flattened_image: FlattenedImage):
    process = await asyncio.create_subprocess_exec(
        "skopeo", "inspect",
        f"docker://{flattened_image.name}:{flattened_image.tag}",
        stdout = asyncio.subprocess.PIPE,
        stderr = asyncio.subprocess.PIPE,
        env = os.environ | { "TMPDIR": tmpdir }
    )

    stdout, stderr = await process.communicate()

    if process.returncode == 0:
        output = SkopeoImageInfo.model_validate_json(stdout)
        flattened_image.digest = output.digest

        return flattened_image
    else:
        print(stderr)
        return None

async def nix_build(tmpdir: str, flattened_image: FlattenedImage):
    process = await asyncio.create_subprocess_exec(
        "nix-prefetch-docker", "--json",
        "--final-image-name", flattened_image.name,
        "--final-image-tag", flattened_image.tag,
        "--image-name", flattened_image.name,
        "--image-digest", flattened_image.digest,
        "--image-tag", flattened_image.tag,
        stdout = asyncio.subprocess.PIPE,
        stderr = asyncio.subprocess.PIPE,
        env = os.environ | { "TMPDIR": tmpdir }
    )

    stdout, stderr = await process.communicate()

    if process.returncode == 0:
        flattened_image.hash = TypeAdapter(dict[str, str]).validate_json(stdout)["hash"]
        return flattened_image
    else:
        print(stderr)
        return None

def print_image_identifiers(images: Images) -> str:
    output: str = ""

    for name, versions in images.items():
        output += f"{name}:\n"
        for tag, _ in versions.items():
            output += f"    {tag}\n"

    return output

def flatten_images(images: Images) -> list[FlattenedImage]:
    flattened_images = []

    for name, versions in images.items():
        for tag, image in versions.items():
            flattened_images.append(FlattenedImage(name = name, tag = tag, **image.model_dump()))

    return flattened_images

def unflatten_images(flattened_images: list[FlattenedImage]) -> Images:
    images: Images = {}

    for flattened_image in flattened_images:
        images |= {
            flattened_image.name: images.get(flattened_image.name, {}) | {
                flattened_image.tag: flattened_image.to_image()
            }
        }

    return images

async def sync_image_versions():
    tmpdir = os.getcwd() + "/tmpdir"
    try:
        if not os.path.exists(tmpdir):
            os.mkdir(tmpdir)

        with open("packages/sources.json", "rb") as images_file:
            sources = TypeAdapter(Sources).validate_json(images_file.read())

        images: Images = {}

        for key, value in sources.items():
            if isinstance(value, str):
                continue

            for image_name, image_version in value.containers.items():
                images.setdefault(image_name, {})
                images[image_name] |= { image_version: ImageSpec(hash = None, digest = None) }

        print(print_image_identifiers(images))

        digests = await asyncio.gather(*map(lambda image: get_image_digest(tmpdir, image), flatten_images(images)))
        hashes = await asyncio.gather(*map(lambda image: nix_build(tmpdir, image), digests))

        with open("packages/images.json", "wb") as images_file:
            final_json = TypeAdapter(Images).dump_json(unflatten_images(hashes), indent = 4)
            images_file.write(final_json)
    finally:
        shutil.rmtree(tmpdir)
