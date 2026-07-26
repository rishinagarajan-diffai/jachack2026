# Patient Zero

**An inconsistency checker for the scientific literature.**

A paper gets overturned. The papers citing it don't. Neither do the papers citing *those*.

Patient Zero takes an overturned finding, drives **upward** through the citation graph, and renders every conclusion that still silently rests on it.

Built in [Jac](https://www.jaseci.org/) for JacHacks SF 2026.

---

## The finding

Seeded with one retracted paper, the tool surfaced this in about four seconds:

| | |
|---|---|
| **Patient zero** | *Pluripotency of mesenchymal stem cells derived from adult marrow*, Nature 2002. **Retracted.** 5,532 citations. |
| **Top affected** | *Minimal criteria for defining multipotent mesenchymal stromal cells*, 2006. **17,794 citations of its own.** |

The paper that defines the criteria for an entire field cites a retracted study, and 17,794 papers stand on top of it.

The crawl also found a **second retraction inside the blast radius** on its own: *Cardiac stem cells in patients with ischaemic cardiomyopathy (SCIPIO)*, retracted, 1,281 citations, two hops out. Nothing in the code looks for that; it fell out of the traversal.

---

## Why Jac

Three things this would have been meaningfully worse without.

**The citation graph is the data model.** `paper +>:Cites():+> cited` persists to `.jac/data` with no database, no schema, no ORM, no migrations. The API gets crawled once; every later run reads local disk. Verified: a second run reports `papers already on disk from last run: 41`.

**Upward propagation is walker semantics.** `Cites` runs citing to cited, so the papers *depending on* a finding are its inbound edges. The whole algorithm is `visit [here <-:Cites:<-]` plus a `skip` to prune non load bearing branches. In Python that is a manual BFS queue, a visited set, and state threaded through every call.

**Post-order aggregation is free.** Exit abilities run LIFO, so `can rollup with Paper exit` gets exposure summed up from descendants without a second reversed pass.

---

## Develop

```bash
jac check .            # type check
jac check . --lint     # lint (add --fix to auto-fix)
jac fmt .              # format
jac test score.test.jac
```

`[check.lint] select = ["all"]` is set in `jac.toml`. The upstream
[jac_site](https://github.com/jaseci-labs/jac_site) additionally enables
`strip-comments` and `strip-docstrings`, which delete every comment and
docstring from `.jac` files. Not enabled here: the comments in this repo carry
information a reader needs.

## Run it

Requires [Jac](https://docs.jaseci.org/quick-guide/install/).

```bash
jac install                              # requests + type stubs
export OPENALEX_MAILTO=you@example.com   # optional, OpenAlex polite pool
jac run build.jac                        # score the graph, write graph.html
open graph.html
```

`build.jac` re-scores and re-renders from the persisted graph in about a second. To crawl a different seed:

```jac
import from crawl { Seed, Expand }

with entry {
    root spawn Seed(wid="W2158048826", reason="retracted");
    root spawn Expand(wid="W2158048826", limit=40);
}
```

No API key is needed for anything in this repo. OpenAlex is open.

---

## Layout

| File | Role |
|---|---|
| `model.jac` | `Paper` node, `Cites: Paper --> Paper` edge |
| `crawl.jac` | `Seed` and `Expand` walkers over the OpenAlex API, idempotent get or create |
| `score.jac` | `DriveUpward`: inbound traversal, per hop decay, pruning, exposure rollup |
| `viz.jac` | Exports one JSON payload into a self contained HTML page |
| `viz_template.html` | 2D and 3D canvas renderer, zero dependencies |
| `build.jac` | `Trace` then `Export` |
| `main.sv.jac` | Server entry point, endpoints not wired yet |
| `score.test.jac` | Test annex, 9 tests, no network required |

## Scoring

```
severity      = max(council verdicts)          # currently a 1.0 placeholder
inconsistency = clamp(decay^hop * severity)    # decay = 0.45
priority      = inconsistency * log(1 + citations)
exposure      = own citations + sum(downstream exposure)
```

`priority` is the ranking. It combines how suspect a paper is with how much rests on it, which is why the 17,794 citation paper tops the list rather than something closer to the seed.

## The visualisation

Self contained HTML, about 50 KB, no CDN and no build step. Hand rolled perspective projection on a 2D canvas: rotation matrix, perspective divide, depth sorted painter's algorithm, alpha and radius falling off with distance.

- **3D mode** turns each hop into a spherical shell, so distance from the retraction is radial depth. Idle orbit pauses whenever you hover or focus a node.
- **2D mode** keeps concentric rings, which reads the hop structure more clearly.
- Click any node or panel row to isolate it and light only its citation edges.
- `D` toggles dimensions, `F` refits, `Esc` clears focus.

---

## Status

Working: crawl, persistence, upward traversal with pruning, exposure rollup, priority ranking, both renderers.

Not yet built:

- **The LLM council.** `direct_severity` is hardcoded to `1.0`, so `inconsistency` is currently a pure function of hop distance and every hop 1 paper reads exactly `0.450`. Three `by llm()` auditors (methods, claim, clinical impact) are designed to replace that one number. Nothing else changes.
- **The resolver.** A ReAct agent that turns a plain English claim into a ranked list of candidate papers, so the entry point is a sentence rather than an OpenAlex id.
- **Server endpoints.** `main.sv.jac` is still the scaffold.

## Known limits

- Hop 1 expansion is capped at the top 40 citers by citation count. It is a stated sample, not full coverage.
- `decay = 0.45` is a tuned constant, not calibrated against anything. It puts hop 3 just under the prune threshold.
- Sparse fields give sparse graphs. A 1982 mathematics paper returns about a dozen citers where the biomedical seed returns 5,512.
- Semantic Scholar citation contexts came back empty in testing, so nothing depends on sentence level citation context.

## Data

[OpenAlex](https://openalex.org/), which is open and needs no key. 116,510 works currently carry `is_retracted: true`.
