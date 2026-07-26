"""Graph model for Patient Zero.

`Cites` runs citing --> cited, so a paper's INBOUND edges are the papers
that depend on it. Driving "upward" is therefore `[p <-:Cites:<-]`.
"""

node Paper {
    has openalex_id: str;
    has title: str;
    has year: int = 0;
    has cited_by_count: int = 0;
    has is_retracted: bool = False;

    # overturn state
    has is_overturned: bool = False;
    has overturn_reason: str = "";

    # propagation state
    has hop: int = 99;
    has direct_severity: float = 1.0;    # placeholder until the council lands
    has inconsistency: float = 0.0;
    has exposure: float = 0.0;
    has pruned: bool = False;
}

edge Cites: Paper --> Paper {
    has load_bearing: float = 0.0;
}
