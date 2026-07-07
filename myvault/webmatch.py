"""Match a website's domain to vault entries.

Deliberately simple (no public-suffix list): we normalize hostnames and treat
an entry as a match when its stored domain equals the page's host, or one is a
sub-domain of the other (so `google.com` matches `accounts.google.com`).
"""

from __future__ import annotations

from urllib.parse import urlparse


def normalize_host(value: str) -> str:
    """Turn a URL, host, or messy 'website' field into a bare lowercase host."""
    if not value:
        return ""
    value = value.strip().lower()
    if "://" not in value:
        value = "//" + value          # let urlparse find the host
    host = urlparse(value).hostname or ""
    if host.startswith("www."):
        host = host[4:]
    return host


def hosts_match(page_host: str, entry_host: str) -> bool:
    page_host = normalize_host(page_host)
    entry_host = normalize_host(entry_host)
    if not page_host or not entry_host:
        return False
    if page_host == entry_host:
        return True
    return (page_host.endswith("." + entry_host)
            or entry_host.endswith("." + page_host))


def entry_hosts(entry) -> list[str]:
    """All hosts an entry could be identified by (its website field)."""
    hosts = []
    for raw in (getattr(entry, "website", ""),):
        h = normalize_host(raw)
        if h:
            hosts.append(h)
    return hosts
