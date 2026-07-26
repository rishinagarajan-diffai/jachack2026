test "clamp01_bounds_both_ends" {
    assert clamp01(-3.0) == 0.0;
    assert clamp01(0.0) == 0.0;
    assert clamp01(0.5) == 0.5;
    assert clamp01(1.0) == 1.0;
    assert clamp01(9.9) == 1.0;
}

test "decay_is_monotonic_and_starts_at_one" {
    assert decay_at(0.45, 0) == 1.0;
    assert decay_at(0.45, 1) > decay_at(0.45, 2);
    assert decay_at(0.45, 2) > decay_at(0.45, 3);
    assert decay_at(0.45, 3) < PRUNE_BELOW;
}

test "prune_threshold_bites_at_hop_three" {
    assert decay_at(DEFAULT_DECAY, 2) >= PRUNE_BELOW;
    assert decay_at(DEFAULT_DECAY, 3) < PRUNE_BELOW;
}

test "priority_rises_with_citations_at_equal_inconsistency" {
    small = Paper(openalex_id="a", cited_by_count=10, inconsistency=0.45);
    large = Paper(openalex_id="b", cited_by_count=10000, inconsistency=0.45);
    assert priority_of(large) > priority_of(small);
}

test "priority_rises_with_inconsistency_at_equal_citations" {
    weak = Paper(openalex_id="a", cited_by_count=500, inconsistency=0.05);
    strong = Paper(openalex_id="b", cited_by_count=500, inconsistency=0.90);
    assert priority_of(strong) > priority_of(weak);
}

test "a_clean_paper_carries_no_priority" {
    assert priority_of(Paper(openalex_id="a", cited_by_count=9999)) == 0.0;
}

test "drive_upward_decays_by_hop_and_prunes_the_tail" {
    seed = (root ++> Paper(openalex_id="seed", is_overturned=True, hop=0)) as Paper;
    h1 = (root ++> Paper(openalex_id="h1", hop=1, cited_by_count=100)) as Paper;
    h2 = (root ++> Paper(openalex_id="h2", hop=2, cited_by_count=100)) as Paper;
    h3 = (root ++> Paper(openalex_id="h3", hop=3, cited_by_count=100)) as Paper;
    h1 +>:Cites():+> seed;
    h2 +>:Cites():+> h1;
    h3 +>:Cites():+> h2;

    seed spawn DriveUpward(decay=0.45);

    assert seed.inconsistency == 1.0;
    assert h1.inconsistency > h2.inconsistency;
    assert not h1.pruned;
    assert not h2.pruned;
    assert h3.pruned;
}

test "exposure_rolls_up_from_descendants" {
    seed = (
        root ++> Paper(openalex_id="s2", is_overturned=True, hop=0, cited_by_count=5)
    ) as Paper;
    kid = (root ++> Paper(openalex_id="k2", hop=1, cited_by_count=7)) as Paper;
    kid +>:Cites():+> seed;

    seed spawn DriveUpward(decay=0.45);

    assert kid.exposure == 7.0;
    assert seed.exposure == 12.0;
}

test "findings_come_back_ranked_and_exclude_the_seed" {
    seed = (root ++> Paper(openalex_id="s3", is_overturned=True, hop=0)) as Paper;
    small = (root ++> Paper(openalex_id="small", hop=1, cited_by_count=10)) as Paper;
    huge = (root ++> Paper(openalex_id="huge", hop=1, cited_by_count=90000)) as Paper;
    small +>:Cites():+> seed;
    huge +>:Cites():+> seed;

    w = DriveUpward(decay=0.45);
    seed spawn w;

    out = w.ranked();
    ids = [f.id for f in out];
    assert "s3" not in ids;
    assert out[0].id == "huge";
    assert out[0].priority > out[-1].priority;
}
