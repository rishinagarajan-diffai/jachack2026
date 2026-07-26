"""Export the scored graph as a self-contained HTML page.

Reads Papers and Cites off the persistent graph, inlines one JSON payload into
viz_template.html, and writes graph.html. No server, no CDN, no CORS.
"""

import json;
import from model { Paper, Cites, PaperView }

obj GraphMeta {
    has seed_title: str = "No seed selected",
        seed_cites: int = 0,
        verified: bool = False,
        n_papers: int = 0,
        n_edges: int = 0,
        top_cites: int = 0,
        retracted_downstream: int = 0;
}

obj GraphPayload {
    has nodes: list[PaperView] = [],
        links: list[dict[str, str]] = [],
        meta: GraphMeta = GraphMeta();
}

def view_dict(v: PaperView) -> dict[str, any] {
    return {
        "id": v.id,
        "title": v.title,
        "year": v.year,
        "cited_by_count": v.cited_by_count,
        "is_retracted": v.is_retracted,
        "is_overturned": v.is_overturned,
        "hop": v.hop,
        "inconsistency": v.inconsistency,
        "exposure": v.exposure,
        "priority": v.priority,
        "pruned": v.pruned
    };
}

def build_payload -> GraphPayload {
    views: list[PaperView] = [];
    links: list[dict[str, str]] = [];
    for p in [root-->[?:Paper]] {
        views.append(p.view());
        for cited in [p->:Cites:->] {
            links.append({"source": p.openalex_id, "target": cited.openalex_id});
        }
    }

    meta = GraphMeta(n_papers=len(views), n_edges=len(links));

    seeds = [
        p
        for p in [root-->[?:Paper]]
        if p.is_overturned
    ];
    if seeds {
        meta.seed_title = seeds[0].clean_title();
        meta.seed_cites = seeds[0].cited_by_count;
        meta.verified = seeds[0].is_retracted;
    }

    affected = [
        v
        for v in views
        if not v.is_overturned
    ];
    ranked: list[PaperView] = sorted(
        affected, key=lambda (v: PaperView) { v.priority; }, reverse=True
    );
    if ranked {
        meta.top_cites = ranked[0].cited_by_count;
    }
    meta.retracted_downstream = len(
        [
            v
            for v in views
            if v.is_retracted and not v.is_overturned
        ]
    );

    return GraphPayload(nodes=views, links=links, meta=meta);
}

def payload_json(p: GraphPayload) -> str {
    return json.dumps(
        {
            "nodes": [view_dict(v) for v in p.nodes],
            "links": p.links,
            "meta": {
                "seed_title": p.meta.seed_title,
                "seed_cites": p.meta.seed_cites,
                "verified": p.meta.verified,
                "n_papers": p.meta.n_papers,
                "n_edges": p.meta.n_edges,
                "top_cites": p.meta.top_cites,
                "retracted_downstream": p.meta.retracted_downstream
            }
        }
    );
}


"""Write graph.html with the current graph baked in."""
walker Export {
    has out: str = "graph.html",
        reports: list[dict[str, any]] = [];

    can go with Root entry {
        payload = build_payload();
        tpl = open("viz_template.html").read();
        open(self.out, "w").write(tpl.replace("__PAYLOAD__", payload_json(payload)));
        report {
            "wrote": self.out,
            "nodes": payload.meta.n_papers,
            "links": payload.meta.n_edges,
            "verified": payload.meta.verified
        };
    }
}
