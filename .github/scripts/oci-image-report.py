#!/usr/bin/env python3
##
# Copyright (C) 2026 Hedera Hashgraph, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##
"""Summarize the linux/amd64 image in an OCI image layout so two builds can be compared file by file.

Usage: oci-image-report.py <oci-layout-dir> <output-dir>

Writes to <output-dir>:
  digest.txt   image manifest digest; reproducible builds of the same commit must produce the same value
  config.json  image config, pretty-printed
  layers.txt   one line per layer: index, digest, compressed size
  files.tsv    one line per layer entry: layer, path, type, mode, uid, gid, size, mtime, link target,
               extended (PAX) headers, and the SHA-256 of regular file contents
"""

import hashlib
import json
import sys
import tarfile
from pathlib import Path

INDEX_MEDIA_TYPES = {
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
}

ENTRY_TYPES = {
    tarfile.REGTYPE: "file",
    tarfile.AREGTYPE: "file",
    tarfile.LNKTYPE: "hardlink",
    tarfile.SYMTYPE: "symlink",
    tarfile.CHRTYPE: "char",
    tarfile.BLKTYPE: "block",
    tarfile.DIRTYPE: "dir",
    tarfile.FIFOTYPE: "fifo",
}


def blob_path(layout: Path, digest: str) -> Path:
    algorithm, encoded = digest.split(":", 1)
    return layout / "blobs" / algorithm / encoded


def load_blob(layout: Path, digest: str) -> dict:
    return json.loads(blob_path(layout, digest).read_bytes())


def find_image_manifest(layout: Path, descriptors: list) -> dict | None:
    """Return the linux/amd64 image manifest descriptor, skipping attestation manifests (platform unknown/unknown)."""
    for descriptor in descriptors:
        if descriptor.get("mediaType") in INDEX_MEDIA_TYPES:
            found = find_image_manifest(layout, load_blob(layout, descriptor["digest"])["manifests"])
            if found:
                return found
            continue
        platform = descriptor.get("platform")
        if platform is None or (platform.get("os"), platform.get("architecture")) == ("linux", "amd64"):
            return descriptor
    return None


def file_sha256(archive: tarfile.TarFile, member: tarfile.TarInfo) -> str:
    if not member.isreg():
        return "-"
    digest = hashlib.sha256()
    with archive.extractfile(member) as content:
        for chunk in iter(lambda: content.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    layout, output = Path(sys.argv[1]), Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)

    index = json.loads((layout / "index.json").read_text())
    descriptor = find_image_manifest(layout, index["manifests"])
    if descriptor is None:
        print("error: no linux/amd64 image manifest found in the OCI layout", file=sys.stderr)
        return 1

    manifest = load_blob(layout, descriptor["digest"])
    config = load_blob(layout, manifest["config"]["digest"])

    (output / "digest.txt").write_text(descriptor["digest"] + "\n")
    (output / "config.json").write_text(json.dumps(config, indent=2, sort_keys=True) + "\n")

    with (output / "layers.txt").open("w") as layers, (output / "files.tsv").open("w") as files:
        for number, layer in enumerate(manifest["layers"]):
            layers.write(f"{number}\t{layer['digest']}\t{layer['size']}\n")
            with blob_path(layout, layer["digest"]).open("rb") as stream, tarfile.open(
                fileobj=stream, mode="r|*"
            ) as archive:
                for member in archive:
                    pax = json.dumps(member.pax_headers, sort_keys=True) if member.pax_headers else "-"
                    fields = [
                        str(number),
                        member.name,
                        ENTRY_TYPES.get(member.type, repr(member.type)),
                        f"{member.mode:o}",
                        str(member.uid),
                        str(member.gid),
                        str(member.size),
                        str(int(member.mtime)),
                        member.linkname or "-",
                        pax,
                        file_sha256(archive, member),
                    ]
                    files.write("\t".join(fields) + "\n")

    print(f"{descriptor['digest']} ({len(manifest['layers'])} layers)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
