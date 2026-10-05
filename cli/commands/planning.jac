"""Scheduling and week commands."""

import from core.planner {
    add_course,
    add_goal,
    clear_day_plan,
    get_day_plan,
    list_courses,
    list_goals,
    log_goal,
    outlook,
    plan_day,
    remove_course,
    reset_all,
    seed_demo,
    unlog_goal
}
import from cli.commands.common {
    BOLD,
    CYAN,
    DIM,
    EXIT_FAILURE,
    EXIT_OK,
    EXIT_USAGE,
    GREEN,
    RED,
    YELLOW,
    clock,
    duration,
    exit_code_for,
    fit,
    heading,
    paint,
    print_tasks,
    short_id,
    warn
}


"""Render a stored or freshly built plan."""
def show_plan(blocks: list[any], summary: str) {
    if not blocks {
        print(paint("  no blocks -- run `hunt plan` to build one", DIM));
        return;
    }
    for block in blocks {
        label = block.label if block.kind == "focus" else paint(block.label, DIM);
        print(
            "  "
                + paint(clock(block.start_min) + "–" + clock(block.end_min), DIM)
                + "  "
                + fit(label, 44)
                + paint(block.rationale, DIM)
        );
    }
    print();
    print(paint("  " + summary, DIM));
}


"""`hunt plan [--minutes N]` -- build today's schedule."""
async def run_plan(minutes: int, show_only: bool) -> int {
    try {
        result = await get_day_plan("") if show_only else await plan_day("", minutes);
    } except Exception as e {
        return exit_code_for(e);
    }
    print();
    print(paint("Day plan · " + result.date, BOLD));
    print();
    show_plan(result.blocks, result.summary);
    if result.unplanned {
        heading("did not fit", len(result.unplanned));
        print_tasks(result.unplanned[:6], "");
    }
    print();
    return EXIT_OK;
}


"""`hunt plan clear`."""
async def run_clear_plan -> int {
    try {
        outcome = await clear_day_plan("");
    } except Exception as e {
        return exit_code_for(e);
    }
    print(outcome.message);
    return EXIT_OK;
}


"""`hunt week [--offset N]` -- seven days of deadlines."""
async def run_week(offset: int) -> int {
    try {
        week = await outlook("", 7, offset);
    } except Exception as e {
        return exit_code_for(e);
    }
    print();
    print(
        paint("Week of " + week.start, BOLD)
            + paint("   " + duration(week.total_minutes) + " of work", DIM)
    );
    for day in week.days {
        marker = paint("▸", YELLOW) if day.is_today else " ";
        label = day.weekday[:3] + " " + day.date[5:];
        head = paint(label, BOLD) if day.is_today else (paint(label, DIM) if day.is_past else label);
        load = paint(duration(day.minutes), DIM) if day.minutes else paint("—", DIM);
        print();
        print(" " + marker + " " + head + "   " + load);
        if not day.tasks {
            continue;
        }
        for task in day.tasks {
            print(
                "      "
                    + paint(short_id(task.id), DIM)
                    + "  "
                    + paint(fit(task.course_code or "—", 10), CYAN)
                    + fit(task.title, 42)
                    + paint(duration(task.estimate_minutes), DIM)
            );
        }
    }
    if week.overdue {
        heading("overdue outside this week", len(week.overdue));
        print_tasks(week.overdue[:6], "");
    }
    if week.undated {
        heading("no deadline yet", len(week.undated));
        print_tasks(week.undated[:6], "");
    }
    print();
    return EXIT_OK;
}


"""`hunt courses` -- the term, with workload rolled up per class."""
async def run_courses -> int {
    try {
        courses = await list_courses();
    } except Exception as e {
        return exit_code_for(e);
    }
    if not courses {
        print(paint("no courses yet -- `hunt course add \"EECS 449\" --title \"...\"`", DIM));
        return EXIT_OK;
    }
    print();
    for course in courses {
        flag = paint("  " + str(course.overdue) + " overdue", RED) if course.overdue else "";
        print(
            "  "
                + paint(fit(course.code, 10), BOLD)
                + fit(course.title, 42)
                + paint(
                    str(course.open_tasks) + " open · " + duration(course.open_minutes),
                    DIM
                )
                + flag
        );
    }
    print();
    return EXIT_OK;
}


"""`hunt course add <code> [--title T] [--credits N]`."""
async def run_add_course(code: str, title: str, credits: int) -> int {
    if not code.strip() {
        warn("hunt course add: a course code is required");
        return EXIT_USAGE;
    }
    try {
        course = await add_course(code.strip(), title, credits, "", "");
    } except Exception as e {
        return exit_code_for(e);
    }
    print(paint("✔", GREEN) + " added " + paint(course.code, BOLD) + " " + paint(course.title, DIM));
    return EXIT_OK;
}


"""`hunt course rm <code>`."""
async def run_remove_course(code: str) -> int {
    try {
        outcome = await remove_course(code.strip());
    } except Exception as e {
        return exit_code_for(e);
    }
    if not outcome.ok {
        warn("hunt: " + outcome.message);
        return EXIT_FAILURE;
    }
    print(paint("✔", GREEN) + " " + outcome.message);
    return EXIT_OK;
}


"""`hunt habits` -- streaks at a glance."""
async def run_habits -> int {
    try {
        goals = await list_goals();
    } except Exception as e {
        return exit_code_for(e);
    }
    if not goals {
        print(paint("no habits yet -- `hunt habit add \"Move for 30 minutes\"`", DIM));
        return EXIT_OK;
    }
    print();
    for goal in goals {
        mark = paint("✔", GREEN) if goal.done_this_period else "·";
        print(
            "  "
                + paint(short_id(goal.id), DIM)
                + "  "
                + mark
                + "  "
                + fit(goal.title, 34)
                + paint(
                    str(goal.streak) + " " + goal.cadence + " streak · " + str(goal.period_count) + "/" + str(goal.target_per_period) + " this period",
                    DIM
                )
        );
    }
    print();
    return EXIT_OK;
}


"""`hunt habit add <title> [--weekly] [--target N]`."""
async def run_add_habit(title: str, weekly: bool, target: int) -> int {
    if not title.strip() {
        warn("hunt habit add: a title is required");
        return EXIT_USAGE;
    }
    try {
        goal = await add_goal(title.strip(), "weekly" if weekly else "daily", target, "");
    } except Exception as e {
        return exit_code_for(e);
    }
    print(paint("✔", GREEN) + " tracking " + paint(goal.title, BOLD) + paint("  (" + goal.cadence + ")", DIM));
    return EXIT_OK;
}


"""`hunt check <habit>` / `hunt uncheck <habit>`."""
async def run_check_habit(needle: str, undo: bool) -> int {
    wanted = needle.strip().lower();
    try {
        goals = await list_goals();
    } except Exception as e {
        return exit_code_for(e);
    }
    matches = [
        g for g in goals if g.id.lower().startswith(wanted) or wanted in g.title.lower()
    ];
    if len(matches) != 1 {
        warn("hunt: \"" + needle + "\" matched " + str(len(matches)) + " habits");
        for goal in goals {
            warn("    " + short_id(goal.id) + "  " + goal.title);
        }
        return EXIT_USAGE;
    }
    try {
        updated = await unlog_goal(matches[0].id, "") if undo else await log_goal(
            matches[0].id, ""
        );
    } except Exception as e {
        return exit_code_for(e);
    }
    if updated is None {
        warn("hunt: that habit no longer exists");
        return EXIT_FAILURE;
    }
    verb = "unchecked" if undo else "checked"; 
    print(
        paint("✔", GREEN)
            + " "
            + verb
            + " "
            + paint(updated.title, BOLD)
            + paint("   " + str(updated.streak) + " " + updated.cadence + " streak", DIM)
    );
    return EXIT_OK;
}


"""`hunt seed` / `hunt reset` -- demo data controls."""
async def run_data(wipe: bool) -> int {
    try {
        outcome = await reset_all() if wipe else await seed_demo();
    } except Exception as e {
        return exit_code_for(e);
    }
    if not outcome.ok {
        warn("hunt: " + outcome.message);
        return EXIT_FAILURE;
    }
    print(paint("✔", GREEN) + " " + outcome.message);
    return EXIT_OK;
}
