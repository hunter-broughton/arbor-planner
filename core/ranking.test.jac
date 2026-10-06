"""Ranking and scheduling -- the rules that decide what to do next."""

import from core.contracts { NO_DUE_DATE, TaskView }


def:priv sample(
    title: str,
    priority: str = "medium",
    kind: str = "task",
    days: int = NO_DUE_DATE,
    minutes: int = 60
) -> TaskView {
    return TaskView(
        id=title,
        title=title,
        kind=kind,
        priority=priority,
        estimate_minutes=minutes,
        days_until=days,
        urgency=urgency(priority, kind, days, minutes)
    );
}

test "priority and kind words are coerced, never rejected" {
    assert clean_priority("URGENT") == "critical";
    assert clean_priority("") == "medium";
    assert clean_priority("low") == "low";
    assert clean_kind("pset") == "assignment";
    assert clean_kind("midterm") == "exam";
    assert clean_kind("nonsense") == "task";
}

test "deadline weight is monotonic and overdue work dominates" {
    assert deadline_weight(-3) > deadline_weight(0);
    assert deadline_weight(0) > deadline_weight(1);
    assert deadline_weight(1) > deadline_weight(3);
    assert deadline_weight(3) > deadline_weight(30);
    assert deadline_weight(NO_DUE_DATE) == 0.0;
    # Capped, so a task forgotten for a year cannot outrank everything forever.
    assert deadline_weight(-400) == deadline_weight(-900);
}

test "urgency separates the obvious cases" {
    overdue = sample("overdue", "medium", "assignment", -2);
    today = sample("today", "medium", "assignment", 0);
    later = sample("later", "medium", "assignment", 20);
    undated = sample("undated", "medium", "assignment");
    assert overdue.urgency > today.urgency;
    assert today.urgency > later.urgency;
    assert later.urgency > undated.urgency;
    # Same deadline, louder priority wins.
    assert sample("a", "critical", "task", 2).urgency > sample("b", "low", "task", 2).urgency;
}

test "rank orders most urgent first and leaves the input alone" {
    items = [
        sample("quiet", "low", "task", 14),
        sample("burning", "critical", "exam", -1),
        sample("soon", "high", "assignment", 1)
    ];
    ordered = rank(items);
    assert [t.title for t in ordered] == ["burning", "soon", "quiet"];
    assert [t.title for t in items] == ["quiet", "burning", "soon"];
}

test "the day schedule respects the window and the budget" {
    tasks = [
        sample("big", "critical", "project", 0, 240),
        sample("small", "high", "admin", 0, 30),
        sample("later", "low", "task", 5, 60)
    ];
    (blocks, unplanned) = schedule_day(tasks, "2026-10-04", 540, 1020, 180);
    focus = [b for b in blocks if b.kind == "focus"];
    assert len(focus) > 0;
    assert focus[0].label == "big";
    # Nothing starts before the day does or runs past its end.
    for block in blocks {
        assert block.start_min >= 540;
        assert block.end_min <= 1020;
        assert block.end_min > block.start_min;
    }
    # Blocks never overlap.
    for index in range(1, len(blocks)) {
        assert blocks[index].start_min >= blocks[index - 1].end_min;
    }
    # The budget is honoured, and nothing is silently dropped.
    assert focus_minutes(blocks) <= 180;
    assert len(focus) + len(unplanned) == 3;
}

test "a zero budget plans nothing and says so" {
    tasks = [sample("anything", "high", "assignment", 0, 60)];
    (blocks, unplanned) = schedule_day(tasks, "2026-10-04", 540, 1320, 0);
    assert blocks == [];
    assert len(unplanned) == 1;
    assert "Nothing to schedule" in plan_summary(blocks, []);
}

test "completed work is never scheduled" {
    done = sample("finished", "critical", "exam", 0, 60);
    done.done = True;
    (blocks, unplanned) = schedule_day([done], "2026-10-04", 540, 1320, 240);
    assert blocks == [];
    assert unplanned == [];
}

test "an appointment lands at its own time and work flows around it" {
    exam = sample("Midterm I", "critical", "exam", 0, 90);
    exam.fixed = True;
    exam.due_date = "2026-10-07";
    exam.due_time = "18:00";
    study = sample("Review the slides", "high", "exam", 0, 240);
    (blocks, _) = schedule_day([exam, study], "2026-10-07", 540, 1320, 300);
    sitting = [b for b in blocks if b.kind == "commitment"];
    assert len(sitting) == 1;
    assert sitting[0].start_min == 18 * 60;
    assert sitting[0].label == "Midterm I";
    # Nothing else may overlap the exam.
    for block in blocks {
        if block.kind == "commitment" {
            continue;
        }
        assert block.end_min <= sitting[0].start_min or block.start_min >= sitting[0].end_min;
    }
    # The studying still got scheduled.
    assert len([b for b in blocks if b.kind == "focus"]) >= 1;
}

test "an appointment on another day is not today's work" {
    exam = sample("Midterm I", "critical", "exam", 2, 90);
    exam.fixed = True;
    exam.due_date = "2026-10-07";
    exam.due_time = "18:00";
    chore = sample("Email the advisor", "high", "admin", 0, 20);
    (blocks, unplanned) = schedule_day([exam, chore], "2026-10-05", 540, 1320, 240);
    # The exam sitting is neither scheduled nor reported as left over -- it
    # simply is not work for today.
    assert [b.label for b in blocks if b.kind != "break"] == ["Email the advisor"];
    assert [t.title for t in unplanned] == [];
}

test "a fixed task with no usable time falls back to ordinary work" {
    odd = sample("Section", "medium", "admin", 0, 60);
    odd.fixed = True;
    odd.due_date = "2026-10-05";
    odd.due_time = "";
    (blocks, _) = schedule_day([odd], "2026-10-05", 540, 1320, 240);
    assert len([b for b in blocks if b.kind == "focus"]) == 1;
    assert len([b for b in blocks if b.kind == "commitment"]) == 0;
}

test "every block carries a reason a person can read" {
    tasks = [sample("late", "high", "assignment", -2, 45)];
    (blocks, _) = schedule_day(tasks, "2026-10-04", 540, 1320, 120);
    assert blocks[0].rationale == "overdue by 2 days";
    assert rationale_for(sample("x", "medium", "task", 0)) == "due today, medium priority";
    assert rationale_for(sample("x", "medium", "task", 1)) == "due tomorrow";
    assert "no deadline" in rationale_for(sample("x"));
}
