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

class ImageSpec(BaseModel):
    hash: str
    digest: str

ImageVersions = dict[str, ImageSpec]
Images = dict[str, ImageVersions]

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

def get_image_identifiers(images: Images) -> list[str]:
    identifiers = []

    for name, versions in images.items():
        for tag, _ in versions.items():
            identifiers.append(f"{name}@{tag}")

    return identifiers

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

async def main():
    tmpdir = os.getcwd() + "/tmpdir"
    try:
        if not os.path.exists(tmpdir):
            os.mkdir(tmpdir)

        with open("packages/images.json", "rb") as images_file:
            images = TypeAdapter(Images).validate_json(images_file.read())

        print(f"discovered images: {', '.join(get_image_identifiers(images))}")

        digests = await asyncio.gather(*map(lambda image: get_image_digest(tmpdir, image), flatten_images(images)))
        hashes = await asyncio.gather(*map(lambda image: nix_build(tmpdir, image), digests))

        final_json = TypeAdapter(Images).dump_json(unflatten_images(hashes))

        with open("packages/images.json", "wb") as images_file:
            images_file.write(final_json)
    finally:
        shutil.rmtree(tmpdir)

asyncio.run(main())
