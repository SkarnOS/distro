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
    finalImageName: str | None = None
    finalImageTag: str | None = None
    hash: str
    imageDigest: str
    imageName: str
    imageTag: str

Images = TypeAdapter(dict[str, ImageSpec])

class SkopeoImageInfo(BaseModel):
    digest: str = Field(alias = "Digest")

async def get_image_digest(tmpdir: str, name: str, image: ImageSpec):
    process = await asyncio.create_subprocess_exec(
        "skopeo", "inspect",
        f"docker://{image.imageName}:{image.imageTag}",
        stdout = asyncio.subprocess.PIPE,
        stderr = asyncio.subprocess.PIPE,
        env = os.environ | { "TMPDIR": tmpdir }
    )

    stdout, stderr = await process.communicate()

    if process.returncode == 0:
        output = SkopeoImageInfo.model_validate_json(stdout)

        return (
            name, output.digest
        )
    else:
        print(stderr)
        return None

async def nix_build(tmpdir: str, name, image: ImageSpec):
    process = await asyncio.create_subprocess_exec(
        "nix-prefetch-docker", "--json",
        "--final-image-tag", image.finalImageTag,
        "--final-image-tag", image.finalImageTag,
        image.imageName, image.imageDigest,
        stdout = asyncio.subprocess.PIPE,
        stderr = asyncio.subprocess.PIPE,
        env = os.environ | { "TMPDIR": tmpdir }
    )

    stdout, stderr = await process.communicate()

    if process.returncode == 0:
        return (
            name, TypeAdapter(dict[str, str]).validate_json(stdout)["hash"]
        )
    else:
        print(stderr)
        return None

async def main():
    tmpdir = os.getcwd() + "/tmpdir"
    try:
        if not os.path.exists(tmpdir):
            os.mkdir(tmpdir)

        with open("packages/images.json", "rb") as images_file:
            images = Images.validate_json(images_file.read())

        digests = dict(await asyncio.gather(*map(lambda image: get_image_digest(tmpdir, image[0], image[1]), images.items())))

        hashes = dict(await asyncio.gather(*map(lambda image: nix_build(tmpdir, image[0], image[1]), images.items())))

        for name, image in images.items():
            image.imageDigest = digests[name]
            image.finalImageTag = image.imageTag
            image.hash = hashes[name]

        with open("packages/images.json", "wb") as images_file:
            images_file.write(Images.dump_json(images))
    finally:
        shutil.rmtree(tmpdir)

asyncio.run(main())
