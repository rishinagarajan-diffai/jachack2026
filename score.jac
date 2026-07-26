"""Deterministic upward propagation. No LLM yet.

`direct_severity` is a hardcoded 1.0 placeholder that the council replaces
later. Everything else here (decay, pruning, post-order exposure rollup,
priority ranking) is the real scoring path.
"""

import math;
import from model { Paper, Cites }

glob PRUNE_BELOW: float = 0.10,
     DEFAULT_DECAY: float = 0.45;

obj Finding {
    has id: str = "",
        title: str = "",
        hop: int = 0,
        inconsistency: float = 0.0,
        cited_by_count: int = 0,
        priority: float = 0.0;
}

def clamp01(x: float) -> float {
    return min(1.0, max(0.0, x));
}

def priority_of(p: Paper) -> float {
    return p.inconsistency * math.log(1.0 + (p.cited_by_count as float));
}

def decay_at(decay: float, hop: int) -> float {
    return decay ** (hop as float);
}


"""Climb inbound Cites edges from every overturned seed, decaying per hop."""
walker DriveUpward {
    has decay: float = DEFAULT_DECAY,
        seen: list[str] = [],
        findings: list[Finding] = [],
        reports: list[list[Finding]] = [];

    can assess with Paper entry {
        if here.openalex_id in self.seen {
            skip;
        }
        self.seen.append(here.openalex_id);

        if here.is_overturned {
            here.inconsistency = 1.0;
            here.pruned = False;
        } else {
            inherited = decay_at(self.decay, here.hop);
            here.inconsistency = clamp01(inherited * here.direct_severity);
            here.pruned = here.inconsistency < PRUNE_BELOW;
        }
        here.priority = priority_of(here);

        if here.pruned {
            skip;
        }
        if not here.is_overturned {
            self.findings.append(
                Finding(
                    id=here.openalex_id,
                    title=here.clean_title(),
                    hop=here.hop,
                    inconsistency=round(here.inconsistency, 3),
                    cited_by_count=here.cited_by_count,
                    priority=round(here.priority, 2)
                )
            );
        }
        visit [here<-:Cites:<-];
    }

    can rollup with Paper exit {
        downstream = 0.0;
        for citer in [here<-:Cites:<-] {
            downstream += citer.exposure;
        }
        here.exposure = (here.cited_by_count as float) + downstream;
    }

    def ranked -> list[Finding] {
        return sorted(
            self.findings, key=lambda (f: Finding) { f.priority; }, reverse=True
        ) as list[Finding];
    }
}


"""Spawn DriveUpward from every seed so callers do not have to find them."""
walker Trace {
    has decay: float = DEFAULT_DECAY,
        reports: list[list[Finding]] = [];

    can go with Root entry {
        w = DriveUpward(decay=self.decay);
        for seed in [
            p
            for p in [root-->[?:Paper]]
            if p.is_overturned
        ] {
            seed spawn w;
        }
        report w.findings;
    }
}
