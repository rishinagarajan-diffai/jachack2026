"""Deterministic upward propagation. No LLM yet.

`direct_severity` is a hardcoded 1.0 placeholder that the council replaces
later. Everything else here (decay, pruning, post-order exposure rollup,
priority ranking) is the real scoring path.
"""

import math;
import from model { Paper, Cites }

glob PRUNE_BELOW: float = 0.10;


def clamp01(x: float) -> float {
    if x < 0.0 { return 0.0; }
    if x > 1.0 { return 1.0; }
    return x;
}

def priority_of(p: Paper) -> float {
    return p.inconsistency * math.log(1.0 + (p.cited_by_count as float));
}


"""Climb inbound Cites edges from every overturned seed, decaying per hop."""
walker DriveUpward {
    has decay: float = 0.45;
    has seen: list[str] = [];
    has findings: list[dict] = [];
    has reports: list[list[dict]] = [];

    can assess with Paper entry {
        if here.openalex_id in self.seen { skip; }
        self.seen.append(here.openalex_id);

        if here.is_overturned {
            here.inconsistency = 1.0;
            here.pruned = False;
        } else {
            inherited = self.decay ** (here.hop as float);
            here.inconsistency = clamp01(inherited * here.direct_severity);
            here.pruned = here.inconsistency < PRUNE_BELOW;
            if here.pruned { skip; }        # not load bearing, stop climbing
            self.findings.append({
                "id": here.openalex_id,
                "title": here.title,
                "hop": here.hop,
                "inconsistency": round(here.inconsistency, 3),
                "cited_by_count": here.cited_by_count,
                "priority": round(priority_of(here), 2)
            });
        }
        visit [here <-:Cites:<-];           # <- UPWARD: papers depending on this one
    }

    # Exit abilities run post-order (LIFO), so citers are already scored here.
    can rollup with Paper exit {
        downstream = 0.0;
        for citer in [here <-:Cites:<-] {
            downstream += citer.exposure;
        }
        here.exposure = (here.cited_by_count as float) + downstream;
    }

    can finish with Root exit {
        self.findings.sort(key=lambda (f: dict) { f["priority"]; }, reverse=True);
        report self.findings;
    }
}


"""Spawn DriveUpward from root so seeds are found automatically."""
walker Trace {
    has decay: float = 0.45;
    has reports: list[list[dict]] = [];

    can go with Root entry {
        w = DriveUpward(decay=self.decay);
        for seed in [root -->[?:Paper, is_overturned == True]] {
            seed spawn w;
        }
        report w.findings;
    }
}
