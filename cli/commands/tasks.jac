"""Task commands: the fast path between a thought and the planner."""

import from core.planner {
    agenda,
    breakdown_task,
    list_tasks,
    quick_add,
    remove_task,
    set_task_done
}
import from cli.commands.common {
    BOLD,
    CYAN,
    DIM,
    EXIT_FAILURE,
    EXIT_OK,
    EXIT_USAGE,
    GREEN,
    YELLOW,
    clock,
    duration,
    exit_code_for,
    heading,
    heading_note,
    paint,
    print_tasks,
    resolve_task,
    short_id,
    task_line,
    warn
}


"""`arbor today` -- the whole day in one screen."""
async def run_today -> int {
    try {
        day = await agenda("");
    } except Exception as e {
        return exit_code_for(e);
    }
    print();
    print(
        paint(day.weekday + ", " + day.date, BOLD)
            + paint(
                "   " + duration(day.load_minutes) + " of work · capacity " + duration(day.capacity_minutes),
                DIM
            )
    );
    if day.headline {
        print();
        print("  " + paint(day.headline, YELLOW) + paint("  [" + ("ai" if day.ai else "rule-based") + "]", DIM));
        print("  " + paint(day.advice, DIM));
    }
    heading("overdue", len(day.overdue));
    print_tasks(day.overdue, "nothing overdue");
    heading("due today", len(day.due_today));
    print_tasks(day.due_today, "nothing due today");
    heading("coming up", len(day.upcoming));
    print_tasks(day.upcoming[:8], "the next ten days are clear");
    if day.blocks {
        heading("day plan", len([b for b in day.blocks if b.kind == "focus"]));
        for block in day.blocks {
            label = block.label if block.kind == "focus" else paint(block.label, DIM);
            print(
                "  "
                    + paint(clock(block.start_min) + "–" + clock(block.end_min), DIM)
                    + "  "
                    + label
            );
        }
    }
    if day.goals {
        kept = len([g for g in day.goals if g.done_this_period]);
        heading_note("habits", str(kept) + " of " + str(len(day.goals)) + " kept");
        for goal in day.goals {
            mark = paint("✔", GREEN) if goal.done_this_period else "·";
            print(
                "  "
                    + paint(short_id(goal.id), DIM)
                    + "  "
                    + mark
                    + "  "
                    + goal.title
                    + paint("   " + str(goal.streak) + " streak", DIM)
            );
        }
    }
    print();
    return EXIT_OK;
}


"""`arbor add "<one line>"` -- natural-language capture from the terminal."""
async def run_add(capture: str) -> int {
    text = capture.strip();
    if not text {
        warn("arbor add: nothing to add");
        return EXIT_USAGE;
    }
    try {
        result = await quick_add(text);
    } except Exception as e {
        return exit_code_for(e);
    }
    if not result.task.id {
        warn("arbor add: " + result.interpreted);
        return EXIT_FAILURE;
    }
    print(
        paint("✔", GREEN)
            + " added "
            + paint(result.task.title, BOLD)
            + paint("  [" + ("ai" if result.ai else "parsed") + "]", DIM)
    );
    print("  " + paint(result.interpreted, DIM));
    print("  " + paint("id " + short_id(result.task.id), DIM));
    return EXIT_OK;
}


"""`arbor ls` -- the open queue, most urgent first."""
async def run_list(include_done: bool, course: str) -> int {
    try {
        tasks = await list_tasks(include_done, course);
    } except Exception as e {
        return exit_code_for(e);
    }
    if not tasks {
        print(paint("nothing here yet -- try `arbor add \"read chapter 7 by friday\"`", DIM));
        return EXIT_OK;
    }
    minutes = sum([t.estimate_minutes for t in tasks if not t.done]);
    print();
    for task in tasks {
        print(task_line(task));
    }
    print();
    print(paint("  " + str(len(tasks)) + " tasks · " + duration(minutes) + " of open work", DIM));
    return EXIT_OK;
}


"""Shared lookup: resolve a user-typed handle against every task."""
async def find(needle: str) -> any {
    tasks = await list_tasks(True, "");
    return resolve_task(needle, tasks);
}


"""`arbor done <id|title>` / `arbor undone <id|title>`."""
async def run_complete(needle: str, done: bool) -> int {
    try {
        task = await find(needle);
        if task is None {
            warn("arbor: no task matched \"" + needle + "\"");
            return EXIT_USAGE;
        }
        updated = await set_task_done(task.id, done);
    } except Exception as e {
        return exit_code_for(e);
    }
    if updated is None {
        warn("arbor: that task no longer exists");
        return EXIT_FAILURE;
    }
    verb = "completed" if done else "reopened";
    print(paint("✔", GREEN) + " " + verb + " " + paint(updated.title, BOLD));
    return EXIT_OK;
}


"""`arbor rm <id|title>`."""
async def run_remove(needle: str) -> int {
    try {
        task = await find(needle);
        if task is None {
            warn("arbor: no task matched \"" + needle + "\"");
            return EXIT_USAGE;
        }
        outcome = await remove_task(task.id);
    } except Exception as e {
        return exit_code_for(e);
    }
    print(paint("✔", GREEN) + " " + outcome.message);
    return EXIT_OK;
}


"""`arbor split <id|title>` -- break a big task into work sessions."""
async def run_split(needle: str) -> int {
    try {
        task = await find(needle);
        if task is None {
            warn("arbor: no task matched \"" + needle + "\"");
            return EXIT_USAGE;
        }
        result = await breakdown_task(task.id);
    } except Exception as e {
        return exit_code_for(e);
    }
    if not result.subtasks {
        warn("arbor split: nothing to split");
        return EXIT_FAILURE;
    }
    print(
        paint(result.parent.title, BOLD)
            + paint("  [" + ("ai" if result.ai else "template") + "]", DIM)
    );
    for step in result.subtasks {
        print(
            "  "
                + paint(short_id(step.id), DIM)
                + "  "
                + step.title
                + paint("   " + duration(step.estimate_minutes) + (("  due " + step.due_date) if step.due_date else ""), DIM)
        );
    }
    return EXIT_OK;
}
