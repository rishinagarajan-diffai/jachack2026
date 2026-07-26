"""Export the scored graph as a self-contained HTML page.

Reads Papers and Cites off the persistent graph, inlines one JSON payload
into viz_template.html, and writes graph.html. No server, no CDN, no CORS.
"""

import json;
import from model { Paper, Cites }
import from score { priority_of }


def node_row(p: Paper) -> dict {
    return {
        "id": p.openalex_id,
        "title": p.title.replace("RETRACTED ARTICLE: ", "").replace("RETRACTED: ", ""),
        "year": p.year,
        "cited_by_count": p.cited_by_count,
        "is_retracted": p.is_retracted,
        "is_overturned": p.is_overturned,
        "hop": p.hop,
        "inconsistency": round(p.inconsistency, 4),
        "exposure": round(p.exposure, 1),
        "priority": round(priority_of(p), 4),
        "pruned": p.pruned
    };
}

def build_payload() -> dict {
    papers = [root -->[?:Paper]];
    nodes = [];
    links = [];
    for p in papers {
        nodes.append(node_row(p));
        for cited in [p ->:Cites:->] {
            links.append({"source": p.openalex_id, "target": cited.openalex_id});
        }
    }

    seeds = [root -->[?:Paper, is_overturned == True]];
    seed_title = "No seed selected";
    seed_cites = 0;
    verified = False;
    if seeds {
        s = seeds[0];
        seed_title = s.title.replace("RETRACTED ARTICLE: ", "").replace("RETRACTED: ", "");
        seed_cites = s.cited_by_count;
        verified = s.is_retracted;
    }

    # top affected excludes the seed itself
    affected = [n for n in nodes if not (n as dict)["is_overturned"]];
    ranked = sorted(affected, key=lambda (n: dict) { n["priority"]; }, reverse=True);
    top_cites = 0;
    if ranked { top_cites = (ranked[0] as dict)["cited_by_count"] as int; }

    further = len([
        n for n in nodes
        if (n as dict)["is_retracted"] and not (n as dict)["is_overturned"]
    ]);

    return {
        "nodes": nodes,
        "links": links,
        "meta": {
            "seed_title": seed_title,
            "seed_cites": seed_cites,
            "verified": verified,
            "n_papers": len(nodes),
            "n_edges": len(links),
            "top_cites": top_cites,
            "retracted_downstream": further
        }
    };
}


"""Write graph.html with the current graph baked in."""
walker Export {
    has out: str = "graph.html";
    has reports: list[dict] = [];

    can go with Root entry {
        payload = build_payload();
        tpl = open("viz_template.html").read();
        html = tpl.replace("__PAYLOAD__", json.dumps(payload));
        open(self.out, "w").write(html);
        meta = payload["meta"] as dict;
        report {
            "wrote": self.out,
            "nodes": meta["n_papers"],
            "links": meta["n_edges"],
            "verified": meta["verified"]
        };
    }
}
