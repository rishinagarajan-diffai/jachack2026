"""Graph model for Patient Zero.

`Cites` runs citing --> cited, so a paper's INBOUND edges are the papers that
depend on it. Driving upward is therefore `[p <-:Cites:<-]`.
"""

obj PaperView {
    has id: str = "",
        title: str = "",
        year: int = 0,
        cited_by_count: int = 0,
        is_retracted: bool = False,
        is_overturned: bool = False,
        hop: int = 0,
        inconsistency: float = 0.0,
        exposure: float = 0.0,
        priority: float = 0.0,
        pruned: bool = False;
}

node Paper {
    has openalex_id: str = "",
        title: str = "",
        year: int = 0,
        cited_by_count: int = 0,
        is_retracted: bool = False,
        is_overturned: bool = False,
        overturn_reason: str = "",
        hop: int = 99,
        direct_severity: float = 1.0,
        inconsistency: float = 0.0,
        exposure: float = 0.0,
        priority: float = 0.0,
        pruned: bool = False;

    def clean_title -> str;
    def view -> PaperView;
}

edge Cites: Paper --> Paper {
    has load_bearing: float = 0.0;
}

impl Paper.clean_title -> str {
    return self.title.replace("RETRACTED ARTICLE: ", "").replace("RETRACTED: ", "");
}

impl Paper.view -> PaperView {
    return PaperView(
        id=self.openalex_id,
        title=self.clean_title(),
        year=self.year,
        cited_by_count=self.cited_by_count,
        is_retracted=self.is_retracted,
        is_overturned=self.is_overturned,
        hop=self.hop,
        inconsistency=round(self.inconsistency, 4),
        exposure=round(self.exposure, 1),
        priority=round(self.priority, 4),
        pruned=self.pruned
    );
}
