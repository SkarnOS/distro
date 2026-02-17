import sys
from typing import Any
import asyncio

from base_types import *
from image_versions import sync_image_versions
from kubernetes_versions import sync_kubernetes_versions

async def main() -> int | Any:
    command = sys.argv[1]

    match command:
        case "sync-image-versions":
            await sync_image_versions()
        case "sync-kubernetes-versions":
            await sync_kubernetes_versions(concurrency_limit = 4)



if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
