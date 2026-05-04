from __future__ import annotations

import json
from typing import Any

from .config import Config
from .downloader import download_urls
from .http import get_bytes


def download_manifest(url: str, config: Config, headers: dict[str, str]) -> int:
    raw = get_bytes(url, headers, timeout=config.timeout, retries=config.retries)
    start = raw.find(b"{")
    if start > 0:
        raw = raw[start:]
    manifest = json.loads(raw.decode("utf-8", errors="replace"))
    image_urls = extract_image_urls(manifest, config)
    print(f"IIIF manifest: {len(image_urls)} image URLs")
    return download_urls(image_urls, config, headers)


def extract_image_urls(manifest: dict[str, Any], config: Config) -> list[str]:
    if "items" in manifest:
        return _extract_v3(manifest, config)
    return _extract_v2(manifest, config)


def _extract_v2(manifest: dict[str, Any], config: Config) -> list[str]:
    urls: list[str] = []
    for sequence in manifest.get("sequences", []):
        for canvas in sequence.get("canvases", []):
            for image in canvas.get("images", []):
                resource = image.get("resource", {})
                service = resource.get("service", {})
                service_id = _service_id(service)
                if service_id:
                    urls.append(_image_url(service_id, config))
                elif resource.get("@id"):
                    urls.append(resource["@id"])
    return urls


def _extract_v3(manifest: dict[str, Any], config: Config) -> list[str]:
    urls: list[str] = []
    for canvas in manifest.get("items", []):
        for annotation_page in canvas.get("items", []):
            for annotation in annotation_page.get("items", []):
                body = annotation.get("body", {})
                if isinstance(body, list):
                    body = body[0] if body else {}
                service = body.get("service") or []
                if isinstance(service, dict):
                    service = [service]
                service_id = _service_id(service[0]) if service else ""
                if service_id:
                    urls.append(_image_url(service_id, config))
                elif body.get("id"):
                    urls.append(body["id"])
    return urls


def _service_id(service: dict[str, Any]) -> str:
    return service.get("@id") or service.get("id") or service.get("Id") or ""


def _image_url(service_id: str, config: Config) -> str:
    return service_id.rstrip("/") + "/" + config.format.lstrip("/")
