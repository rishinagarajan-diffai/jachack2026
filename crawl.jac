"""OpenAlex crawl: seed an overturned paper, expand its inbound citers.

Everything here is deterministic, with no LLM. The graph persists to .jac/data,
so we crawl the API once and traverse locally for the rest of the day.
"""

import os;
import requests;
import from model { Paper, Cites }

glob API: str = "https://api.openalex.org";
# OpenAlex asks for a contact address to put you in its faster "polite pool".
# Kept in the environment so it is not committed: export OPENALEX_MAILTO=you@example.com
glob MAILTO: str = os.environ.get("OPENALEX_MAILTO", "");
glob SELECT: str = "id,doi,title,publication_year,cited_by_count,is_retracted";


# OpenAlex ids come back as full URLs; keep the W-number.
def short_id(full: str) -> str {
    return full.split("/")[-1];
}

def polite(extra: dict) -> dict {
    if MAILTO { extra["mailto"] = MAILTO; }
    return extra;
}

def fetch_work(wid: str) -> dict {
    r = requests.get(
        f"{API}/works/{wid}",
        params=polite({"select": SELECT}),
        timeout=30
    );
    r.raise_for_status();
    return r.json() as dict;
}

# Papers citing `wid`, richest-cited first so a cap keeps the influential ones.
def fetch_citers(wid: str, limit: int) -> list[dict] {
    r = requests.get(
        f"{API}/works",
        params=polite({
            "filter": f"cites:{wid}",
            "per-page": limit,
            "sort": "cited_by_count:desc",
            "select": SELECT
        }),
        timeout=60
    );
    r.raise_for_status();
    payload = r.json() as dict;
    return payload["results"] as list[dict];
}

def find_paper(wid: str) -> Paper | None {
    hits = [root -->[?:Paper, openalex_id == wid]];
    if hits { return hits[0]; }
    return None;
}

# Get-or-create by OpenAlex id. Idempotent, so re-crawling never duplicates.
def upsert(row: dict, hop: int) -> Paper {
    wid = short_id(row["id"] as str);
    found = find_paper(wid);
    if found is not None {
        if hop < found.hop { found.hop = hop; }
        return found;
    }
    raw_title = row.get("title") or "(untitled)";
    return (root ++> Paper(
        openalex_id=wid,
        title=raw_title as str,
        year=(row.get("publication_year") or 0) as int,
        cited_by_count=(row.get("cited_by_count") or 0) as int,
        is_retracted=(row.get("is_retracted") or False) as bool,
        hop=hop
    )) as Paper;
}


"""Mark one paper as the overturned origin."""
walker Seed {
    has wid: str;
    has reason: str = "retracted";
    has reports: list[dict] = [];

    can go with Root entry {
        row = fetch_work(self.wid);
        p = upsert(row, 0);
        p.is_overturned = True;
        p.overturn_reason = self.reason;
        p.hop = 0;
        p.inconsistency = 1.0;
        report {
            "id": p.openalex_id,
            "title": p.title,
            "year": p.year,
            "cited_by_count": p.cited_by_count,
            "is_retracted": p.is_retracted
        };
    }
}


"""One hop upward: pull the papers citing `wid` and wire them in."""
walker Expand {
    has wid: str;
    has limit: int = 40;
    has reports: list[dict] = [];

    can go with Root entry {
        target = find_paper(self.wid);
        if target is None {
            report {"error": f"{self.wid} not in graph - seed it first"};
            return;
        }
        next_hop = target.hop + 1;
        rows = fetch_citers(self.wid, self.limit);
        added = 0;
        for row in rows {
            citer = upsert(row, next_hop);
            if citer.openalex_id == target.openalex_id { continue; }
            already = [citer ->:Cites:->[?:Paper, openalex_id == target.openalex_id]];
            if already { continue; }
            citer +>:Cites():+> target;
            added += 1;
        }
        report {"target": self.wid, "citers_added": added, "hop": next_hop};
    }
}
