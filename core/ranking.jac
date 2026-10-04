"""Ranking and day-scheduling rules.

Pure functions over `TaskView`s: no graph reads, no network, no clock of
their own. That keeps the interesting logic -- what counts as urgent, and how
a day gets carved into blocks -- unit-testable in isolation, and it means the
AI planner in `core/ai.jac` has a deterministic partner it can fall back to
whenever a model is unavailable or returns something unusable.
"""

import from core.contracts { BlockView, NO_DUE_DATE, TaskView }

glob MIN_BLOCK: int = 20,
     MAX_BLOCK: int = 90,
     SHORT_BREAK: int = 10,
     LONG_BREAK: int = 25,
     BLOCKS_BEFORE_LONG_BREAK: int = 2;

glob PRIORITY_WEIGHT: dict[str, float] = {
    "critical": 46.0,
    "high": 28.0,
    "medium": 14.0,
    "low": 5.0
};

glob KIND_WEIGHT: dict[str, float] = {
    "exam": 18.0,
    "assignment": 11.0,
    "project": 9.0,
    "reading": 5.0,
    "admin": 3.0,
    "fitness": 2.0,
    "personal": 1.0,
    "social": 1.0,
    "task": 0.0
};

glob VALID_PRIORITIES: list[str] = ["low", "medium", "high", "critical"];

glob VALID_KINDS: list[str] = [
    "assignment",
    "exam",
    "reading",
    "project",
    "admin",
    "personal",
    "fitness",
    "social",
    "task"
];


"""Coerce arbitrary text to one of the four known priorities."""
def:priv clean_priority(value: str) -> str {
    text = (value or "").strip().lower();
    if text in VALID_PRIORITIES {
        return text;
    }
    if text in ["urgent", "asap", "critical!", "highest"] {
        return "critical";
    }
    if text in ["med", "normal", "default"] {
        return "medium";
    }
    return "medium";
}


"""Coerce arbitrary text to one of the known task kinds."""
def:priv clean_kind(value: str) -> str {
    text = (value or "").strip().lower();
    if text in VALID_KINDS {
        return text;
    }
    if text in ["hw", "homework", "pset", "problem set", "lab"] {
        return "assignment";
    }
    if text in ["midterm", "final", "quiz", "test"] {
        return "exam";
    }
    if text in ["read", "chapter", "paper"] {
        return "reading";
    }
    if text in ["workout", "gym", "run"] {
        return "fitness";
    }
    return "task";
}


"""How much the deadline alone contributes to urgency.

Overdue work dominates, and each further day late adds more, but the term is
capped so a task forgotten for a month cannot permanently crowd out a midterm
tomorrow.
"""
def:priv deadline_weight(days_until: int) -> float {
    if days_until == NO_DUE_DATE {
        return 0.0;
    }
    if days_until < 0 {
        return min(96.0, 64.0 + 4.0 * float(-days_until));
    }
    if days_until == 0 {
        return 52.0;
    }
    if days_until == 1 {
        return 36.0;
    }
    if days_until <= 3 {
        return 24.0;
    }
    if days_until <= 7 {
        return 13.0;
    }
    if days_until <= 14 {
        return 6.0;
    }
    return 2.0;
}


"""Blend deadline, priority, kind and size into one comparable score."""
def:priv urgency(priority: str, kind: str, days_until: int, estimate_minutes: int) -> float {
    score = deadline_weight(days_until);
    score += PRIORITY_WEIGHT.get(clean_priority(priority), 14.0);
    score += KIND_WEIGHT.get(clean_kind(kind), 0.0);
    score += min(6.0, float(max(0, estimate_minutes)) / 45.0);
    return round(score, 2);
}


"""Sort key: most urgent first, then soonest, then alphabetical."""
def:priv rank_key(task: TaskView) -> tuple[float, int, str] {
    return (-task.urgency, task.days_until, task.title.lower());
}


"""Return `tasks` ordered most-urgent-first, leaving the input untouched."""
def:priv rank(tasks: list[TaskView]) -> list[TaskView] {
    return sorted(tasks, key=rank_key);
}


"""One short phrase explaining why a task earned its slot."""
def:priv rationale_for(task: TaskView) -> str {
    if task.days_until == NO_DUE_DATE {
        return f"{task.priority} priority, no deadline yet";
    }
    if task.days_until < 0 {
        late = -task.days_until;
        unit = "day" if late == 1 else "days";
        return f"overdue by {late} {unit}";
    }
    if task.days_until == 0 {
        return f"due today, {task.priority} priority";
    }
    if task.days_until == 1 {
        return "due tomorrow";
    }
    return f"due in {task.days_until} days";
}


"""How long a single sitting on this task should run."""
def:priv slot_length(task: TaskView, remaining: int) -> int {
    wanted = max(MIN_BLOCK, min(MAX_BLOCK, task.estimate_minutes));
    return min(wanted, remaining);
}


"""Carve a day into focus blocks, most urgent work first.

`cursor` walks forward from `day_start`; each task gets at most `MAX_BLOCK`
minutes before a break is inserted, and the walk stops once either the
day window or the user's declared capacity runs out. Tasks that never got a
slot come back in the second element so the caller can show them honestly
rather than silently dropping them.
"""
def:priv schedule_day(
    tasks: list[TaskView],
    date: str,
    day_start: int,
    day_end: int,
    capacity_minutes: int
) -> tuple[list[BlockView], list[TaskView]] {
    ordered = rank([t for t in tasks if not t.done]);
    blocks: list[BlockView] = [];
    unplanned: list[TaskView] = [];
    cursor = day_start;
    budget = max(0, capacity_minutes);
    placed = 0;
    for task in ordered {
        if budget < MIN_BLOCK or cursor + MIN_BLOCK > day_end {
            unplanned.append(task);
            continue;
        }
        length = slot_length(task, min(budget, day_end - cursor));
        if length < MIN_BLOCK {
            unplanned.append(task);
            continue;
        }
        blocks.append(
            BlockView(
                label=task.title,
                date=date,
                start_min=cursor,
                end_min=cursor + length,
                task_id=task.id,
                kind="focus",
                rationale=rationale_for(task)
            )
        );
        cursor += length;
        budget -= length;
        placed += 1;
        pause = LONG_BREAK if placed % BLOCKS_BEFORE_LONG_BREAK == 0 else SHORT_BREAK;
        if budget >= MIN_BLOCK and cursor + pause + MIN_BLOCK <= day_end {
            blocks.append(
                BlockView(
                    label="Break",
                    date=date,
                    start_min=cursor,
                    end_min=cursor + pause,
                    task_id="",
                    kind="break",
                    rationale="recover before the next block"
                )
            );
            cursor += pause;
        }
    }
    return (blocks, unplanned);
}


"""Total minutes of actual focus time in a block list."""
def:priv focus_minutes(blocks: list[BlockView]) -> int {
    return sum([b.end_min - b.start_min for b in blocks if b.kind == "focus"]);
}


"""A one-line readout of what the schedule accomplishes."""
def:priv plan_summary(blocks: list[BlockView], unplanned: list[TaskView]) -> str {
    focus = [b for b in blocks if b.kind == "focus"];
    if not focus {
        return "Nothing to schedule -- your queue is clear for this window.";
    }
    minutes = focus_minutes(blocks);
    hours = round(float(minutes) / 60.0, 1);
    head = f"{len(focus)} focus blocks, {hours}h of work";
    if unplanned {
        return head + f" -- {len(unplanned)} left over, try a longer window.";
    }
    return head + " -- everything open fits in today.";
}
