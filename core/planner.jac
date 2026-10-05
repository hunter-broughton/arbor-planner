"""The HunterPlan planner service -- the single source of truth for all four apps.

This module is the entry point of the `planner` service app declared in
`jac.toml`. The web frontend, the mobile app and the CLI are all clients of
it: none of them owns a store, none of them reimplements a rule, and all
three see the same graph because every endpoint here runs against the
caller's own `root`.

Storage is the graph itself. A signed-in user's subgraph looks like:

    root
     |- Profile                      capacity and working hours
     |- Course  --Assigned-->  Task  coursework, linked to its course
     |- Task                         everything else, and every subtask
     |     \\--Splits-->  Task        a breakdown's children
     |- DayPlan --Scheduled--> Block  one plan per calendar day
     \\- Goal    --Logged-->  Checkin habits and their streaks

Every task also hangs directly off `root`, so a lookup by id is one filtered
query rather than a graph search, while the `Assigned` edge carries the
course relationship. `Agenda` and `Outlook` below are the two places where
walking the graph beats querying it, and they are private walkers spawned
in-process: the endpoints stay typed functions so that three different client
languages get `agenda.overdue[0].title` instead of `result.reports[0]`.
"""

import from core.ai {
    Briefing,
    breakdown,
    briefing,
    interpret,
    kind_name,
    priority_name,
    ai_available,
    ai_model_name
}
import from core.contracts {
    AgendaView,
    BlockView,
    CourseView,
    DayBucket,
    GoalView,
    NO_DUE_DATE,
    OpResult,
    PlanResult,
    ProfileView,
    QuickAddResult,
    BreakdownResult,
    StatusView,
    TaskView,
    WeekView
}
import from core.ranking {
    clean_kind,
    clean_priority,
    focus_minutes,
    plan_summary,
    rank,
    schedule_day,
    urgency
}
import from core.timeutil {
    days_between,
    fmt_minutes,
    normalize_date,
    now_iso,
    pretty_date,
    shift_days,
    today_iso,
    week_start,
    weekday_name
}

# Michigan maize and neon blue first, then colours that hold up against a
# dark blue ground -- the same family the clients paint their chrome in.
glob COURSE_PALETTE: list[str] = [
    "#ffcb05",
    "#3399ff",
    "#00ff94",
    "#ff6b9d",
    "#b794f6",
    "#ff9f43",
    "#4fd1c5",
    "#f6e05e"
];

glob DEFAULT_CAPACITY: int = 240,
     DEFAULT_DAY_START: int = 540,
     DEFAULT_DAY_END: int = 1320,
     UPCOMING_WINDOW: int = 10,
     MAX_TITLE: int = 160,
     MAX_NOTES: int = 2000;

# --- Graph ------------------------------------------------------------------

node Profile {
    """Per-user planner settings. Exactly one hangs off each root."""

    has display_name: str = "",
        daily_capacity_minutes: int = DEFAULT_CAPACITY,
        day_start_min: int = DEFAULT_DAY_START,
        day_end_min: int = DEFAULT_DAY_END,
        created_at: str = "";
}

node Course {
    """A class the student is taking this term."""

    has code: str = "",
        title: str = "",
        credits: int = 0,
        color: str = "#0f766e",
        term: str = "",
        created_at: str = "";
}

node Task {
    """One unit of work. Subtasks are Tasks too, linked by a `Splits` edge."""

    has title: str = "",
        notes: str = "",
        kind: str = "task",
        priority: str = "medium",
        due_date: str = "",
        due_time: str = "",
        estimate_minutes: int = 30,
        done: bool = False,
        done_at: str = "",
        created_at: str = "",
        origin: str = "manual";
}

node DayPlan {
    """A schedule for one calendar date."""

    has date: str = "",
        summary: str = "",
        ai: bool = False,
        created_at: str = "";
}

node Block {
    """A slot on a day plan, in minutes from midnight."""

    has label: str = "",
        start_min: int = 0,
        end_min: int = 0,
        task_id: str = "",
        kind: str = "focus",
        rationale: str = "";
}

node Goal {
    """A habit to keep up, checked off per day or per week."""

    has title: str = "",
        cadence: str = "daily",
        target_per_period: int = 1,
        color: str = "#00ff94",
        created_at: str = "";
}

node Checkin {
    """One day on which a goal was met."""

    has date: str = "",
        created_at: str = "";
}

edge Assigned: Course --> Task {}

edge Splits: Task --> Task {}

edge Scheduled: DayPlan --> Block {}

edge Logged: Goal --> Checkin {}

# --- Private helpers ---------------------------------------------------------
#
# Plain `def` means private: never an endpoint, never on the bridge surface.

"""The caller's profile, created on first touch."""
def:priv profile_node -> Profile {
    found = [root-->][?:Profile];
    if found {
        return found[0];
    }
    return (root ++> Profile(created_at=now_iso())) as Profile;
}


"""Every task under the caller's root."""
def:priv all_tasks -> list[Task] {
    return [root-->][?:Task];
}


"""Every course under the caller's root, ordered by code."""
def:priv all_courses -> list[Course] {
    return sorted([root-->][?:Course], key=course_sort_key);
}


"""Sort courses by their code."""
def:priv course_sort_key(course: Course) -> str {
    return course.code.upper();
}


"""Every goal under the caller's root."""
def:priv all_goals -> list[Goal] {
    return [root-->][?:Goal];
}


"""The course a task belongs to, or None when it is freestanding."""
def:priv course_of(task: Task) -> Course | None {
    owners = [task<-:Assigned:<-];
    return owners[0] if owners else None;
}


"""The parent of a subtask, or None for a top-level task."""
def:priv parent_of(task: Task) -> Task | None {
    parents = [task<-:Splits:<-];
    return parents[0] if parents else None;
}


"""Find one of the caller's tasks by id."""
def:priv task_by_id(task_id: str) -> Task | None {
    for task in all_tasks() {
        if jid(task) == task_id {
            return task;
        }
    }
    return None;
}


"""Find one of the caller's courses by id, or by course code."""
def:priv course_by_id(course_id: str) -> Course | None {
    if not course_id {
        return None;
    }
    wanted = course_id.strip().lower();
    for course in all_courses() {
        if jid(course) == course_id or course.code.lower() == wanted {
            return course;
        }
    }
    return None;
}


"""Find one of the caller's goals by id."""
def:priv goal_by_id(goal_id: str) -> Goal | None {
    for goal in all_goals() {
        if jid(goal) == goal_id {
            return goal;
        }
    }
    return None;
}


"""The stored plan for a date, or None."""
def:priv plan_by_date(date: str) -> DayPlan | None {
    for plan in [root-->][?:DayPlan] {
        if plan.date == date {
            return plan;
        }
    }
    return None;
}


"""Days from `today` until a task is due; NO_DUE_DATE when it has no deadline."""
def:priv days_until(task: Task, today: str) -> int {
    if not task.due_date {
        return NO_DUE_DATE;
    }
    return days_between(today, task.due_date);
}


"""Denormalize a Task node into the view every client reads."""
def:priv task_view(task: Task, today: str) -> TaskView {
    gap = days_until(task, today);
    course = course_of(task);
    parent = parent_of(task);
    return TaskView(
        id=jid(task),
        title=task.title,
        notes=task.notes,
        kind=task.kind,
        priority=task.priority,
        due_date=task.due_date,
        due_time=task.due_time,
        estimate_minutes=task.estimate_minutes,
        done=task.done,
        done_at=task.done_at,
        created_at=task.created_at,
        course_id=jid(course) if course is not None else "",
        course_code=course.code if course is not None else "",
        course_color=course.color if course is not None else "#64748b",
        parent_id=jid(parent) if parent is not None else "",
        origin=task.origin,
        days_until=gap,
        urgency=0.0 if task.done else urgency(
            task.priority, task.kind, gap, task.estimate_minutes
        )
    );
}


"""Denormalize a Course node, rolling up the workload hanging off it."""
def:priv course_view(course: Course, today: str) -> CourseView {
    open_tasks = [t for t in [course->:Assigned:->] if not t.done];
    overdue = 0;
    this_week = 0;
    minutes = 0;
    for task in open_tasks {
        minutes += task.estimate_minutes;
        gap = days_until(task, today);
        if gap != NO_DUE_DATE and gap < 0 {
            overdue += 1;
        } elif gap != NO_DUE_DATE and 0 <= gap <= 7 {
            this_week += 1;
        }
    }
    return CourseView(
        id=jid(course),
        code=course.code,
        title=course.title,
        credits=course.credits,
        color=course.color,
        term=course.term,
        open_tasks=len(open_tasks),
        open_minutes=minutes,
        overdue=overdue,
        due_this_week=this_week
    );
}


"""The period key a check-in counts toward: the date, or its week's Monday."""
def:priv period_key(goal: Goal, date: str) -> str {
    return week_start(date) if goal.cadence == "weekly" else date;
}


"""Consecutive periods, ending today, in which the goal hit its target."""
def:priv streak_for(goal: Goal, dates: list[str], today: str) -> int {
    step = 7 if goal.cadence == "weekly" else 1;
    counts: dict[str, int] = {};
    for date in dates {
        key = period_key(goal, date);
        counts[key] = counts.get(key, 0) + 1;
    }
    target = max(1, goal.target_per_period);
    cursor = period_key(goal, today);
    run = 0;
    # Today only breaks a streak once it is over; an unfinished today is
    # simply not counted yet.
    if counts.get(cursor, 0) < target {
        cursor = period_key(goal, shift_days(today, -step));
    }
    while counts.get(cursor, 0) >= target {
        run += 1;
        cursor = period_key(goal, shift_days(cursor, -step));
    }
    return run;
}


"""Denormalize a Goal node and compute its streak from its check-ins."""
def:priv goal_view(goal: Goal, today: str) -> GoalView {
    dates = sorted([c.date for c in [goal->:Logged:->]]);
    current = period_key(goal, today);
    done_now = len([d for d in dates if period_key(goal, d) == current]);
    return GoalView(
        id=jid(goal),
        title=goal.title,
        cadence=goal.cadence,
        target_per_period=goal.target_per_period,
        color=goal.color,
        streak=streak_for(goal, dates, today),
        period_count=done_now,
        done_this_period=done_now >= max(1, goal.target_per_period),
        history=dates[-30:],
        active=True
    );
}


"""Denormalize a scheduled Block."""
def:priv block_view(block: Block, date: str) -> BlockView {
    return BlockView(
        id=jid(block),
        label=block.label,
        date=date,
        start_min=block.start_min,
        end_min=block.end_min,
        task_id=block.task_id,
        kind=block.kind,
        rationale=block.rationale
    );
}


"""Clamp and tidy free text coming off the wire."""
def:priv clean_text(value: str, limit: int) -> str {
    return (value or "").strip()[:limit];
}


"""Attach a task to a course, replacing any previous assignment."""
def:priv assign_course(task: Task, course: Course | None) {
    del [edge task<-:Assigned:<-];
    if course is not None {
        course +>: Assigned() :+> task;
    }
}

# --- Walkers -----------------------------------------------------------------
#
# These two are the places where walking beats querying: one pass over the
# subgraph assembles a whole screen, courses roll their own tasks up, and the
# `Root exit` ability fires once the traversal is finished. They stay private
# (`walker`, not `walker:pub`) and are spawned in-process by the endpoints
# below, so the four clients get a typed return value instead of the
# `result.reports[0]` unwrap a walker endpoint would force on all of them.

walker:priv Agenda {
    """Assemble one day's screen in a single pass over the user's subgraph."""

    has date: str = "",
        seen: list[str] = [],
        tasks: list[TaskView] = [],
        goals: list[GoalView] = [],
        courses: list[CourseView] = [],
        blocks: list[BlockView] = [],
        result: AgendaView = AgendaView();

    can start with Root entry {
        if not self.date {
            self.date = today_iso();
        }
        visit [-->];
    }

    can on_course with Course entry {
        self.courses.append(course_view(here, self.date));
        visit [here->:Assigned:->];
    }

    can on_task with Task entry {
        key = jid(here);
        # Coursework is reachable twice -- once from root, once through its
        # course -- so the first arrival wins and the second is dropped.
        if key in self.seen {
            skip;
        }
        self.seen.append(key);
        self.tasks.append(task_view(here, self.date));
    }

    can on_goal with Goal entry {
        self.goals.append(goal_view(here, self.date));
    }

    can on_plan with DayPlan entry {
        if here.date != self.date {
            skip;
        }
        visit [here->:Scheduled:->];
    }

    can on_block with Block entry {
        self.blocks.append(block_view(here, self.date));
    }

    # `Root exit` fires after the whole traversal, so everything the walker
    # gathered is in hand. The value comes back on a `has` field rather than
    # through `report`, because the report channel also echoes each payload to
    # the server's stdout and these walkers run on every page load.
    can finish with Root exit {
        self.result = assemble_agenda(
            self.date, self.tasks, self.goals, self.courses, self.blocks
        );
    }
}

walker:priv Outlook {
    """Bucket the next `span` days of work, course by course."""

    has start: str = "",
        span: int = 7,
        seen: list[str] = [],
        tasks: list[TaskView] = [],
        result: WeekView = WeekView();

    can start with Root entry {
        if not self.start {
            self.start = week_start(today_iso());
        }
        visit [-->];
    }

    can on_course with Course entry {
        visit [here->:Assigned:->];
    }

    can on_task with Task entry {
        key = jid(here);
        if key in self.seen {
            skip;
        }
        self.seen.append(key);
        if not here.done {
            self.tasks.append(task_view(here, today_iso()));
        }
    }

    can finish with Root exit {
        self.result = assemble_week(self.start, self.span, self.tasks);
    }
}


"""A compact digest of the day, for the briefing model to read."""
def:priv agenda_context(
    date: str,
    capacity: int,
    overdue: list[TaskView],
    due_today: list[TaskView],
    upcoming: list[TaskView],
    load: int
) -> str {
    lines = [
        f"Date: {pretty_date(date)} ({weekday_name(date)})",
        f"Daily capacity: {fmt_minutes(capacity)}",
        f"Planned load today: {fmt_minutes(load)}"
    ];
    for (label, group) in [
        ("OVERDUE", overdue),
        ("DUE TODAY", due_today),
        ("UPCOMING", upcoming[:6])
    ] {
        if not group {
            continue;
        }
        lines.append(label + ":");
        for task in group {
            course = f"[{task.course_code}] " if task.course_code else "";
            when = task.due_date or "no deadline";
            lines.append(
                f"  - {course}{task.title} ({task.kind}, {task.priority}, "
                    + f"{fmt_minutes(task.estimate_minutes)}, due {when})"
            );
        }
    }
    return "\n".join(lines);
}


"""Bucket the collected tasks into the shape the today screen wants."""
def:priv assemble_agenda(
    date: str,
    tasks: list[TaskView],
    goals: list[GoalView],
    courses: list[CourseView],
    blocks: list[BlockView]
) -> AgendaView {
    settings = profile_node();
    open_tasks = [t for t in tasks if not t.done];
    overdue = rank(
        [t for t in open_tasks if t.days_until != NO_DUE_DATE and t.days_until < 0]
    );
    due_today = rank([t for t in open_tasks if t.days_until == 0]);
    upcoming = rank(
        [
            t
            for t in open_tasks
            if t.days_until == NO_DUE_DATE or 0 < t.days_until <= UPCOMING_WINDOW
        ]
    );
    completed = [t for t in tasks if t.done and t.done_at[:10] == date];
    load = sum([t.estimate_minutes for t in overdue + due_today]);
    capacity = settings.daily_capacity_minutes;
    top = (overdue + due_today + upcoming);
    headline_task = top[0].title if top else "";
    note: Briefing = briefing(
        agenda_context(date, capacity, overdue, due_today, upcoming, load),
        len(overdue),
        len(due_today),
        len(upcoming),
        load,
        capacity,
        headline_task
    );
    return AgendaView(
        date=date,
        weekday=weekday_name(date),
        overdue=overdue,
        due_today=due_today,
        upcoming=upcoming[:UPCOMING_WINDOW],
        completed_today=completed,
        blocks=sorted(blocks, key=block_sort_key),
        goals=sorted(goals, key=goal_sort_key),
        courses=courses,
        recent_days=[shift_days(date, offset) for offset in range(-13, 1)],
        load_minutes=load,
        capacity_minutes=capacity,
        done_minutes=sum([t.estimate_minutes for t in completed]),
        headline=note.headline,
        advice=note.advice,
        ai=note.ai
    );
}


"""Order blocks by their start time."""
def:priv block_sort_key(block: BlockView) -> int {
    return block.start_min;
}


"""Order goals so unfinished habits float to the top."""
def:priv goal_sort_key(goal: GoalView) -> tuple[bool, str] {
    return (goal.done_this_period, goal.title.lower());
}


"""Lay collected tasks out across `span` days starting at `start`."""
def:priv assemble_week(start: str, span: int, tasks: list[TaskView]) -> WeekView {
    today = today_iso();
    buckets: list[DayBucket] = [];
    busiest = "";
    busiest_minutes = -1;
    for offset in range(max(1, span)) {
        date = shift_days(start, offset);
        day_tasks = rank([t for t in tasks if t.due_date == date]);
        minutes = sum([t.estimate_minutes for t in day_tasks]);
        if minutes > busiest_minutes {
            busiest_minutes = minutes;
            busiest = date;
        }
        buckets.append(
            DayBucket(
                date=date,
                weekday=weekday_name(date),
                is_today=date == today,
                is_past=days_between(today, date) < 0,
                tasks=day_tasks,
                minutes=minutes
            )
        );
    }
    window = [b.date for b in buckets];
    return WeekView(
        start=start,
        days=buckets,
        undated=rank([t for t in tasks if not t.due_date]),
        overdue=rank(
            [
                t
                for t in tasks
                if t.due_date and t.due_date not in window
                    and days_between(today, t.due_date) < 0
            ]
        ),
        total_minutes=sum([b.minutes for b in buckets]),
        busiest=busiest if busiest_minutes > 0 else ""
    );
}

# --- Endpoints ---------------------------------------------------------------
#
# `def:protect` = JWT required, and `root` is the caller's own graph, so two
# students running the same deployment never see each other's work. This is
# the entire API surface: the web pages, the phone screens and the CLI all
# call these same functions, the first two as generated client stubs and the
# third over the app bridge.

"""Create and store a task, wiring up its course link."""
def:priv create_task(
    title: str,
    notes: str,
    kind: str,
    priority: str,
    due_date: str,
    due_time: str,
    estimate_minutes: int,
    course: Course | None,
    origin: str
) -> Task {
    task = (
        root ++> Task(
            title=clean_text(title, MAX_TITLE) or "Untitled task",
            notes=clean_text(notes, MAX_NOTES),
            kind=clean_kind(kind),
            priority=clean_priority(priority),
            due_date=normalize_date(due_date),
            due_time=clean_text(due_time, 5),
            estimate_minutes=max(5, min(1440, estimate_minutes)),
            created_at=now_iso(),
            origin=origin
        )
    ) as Task;
    assign_course(task, course);
    return task;
}


"""True when a task has been broken down and its children carry the work."""
def:priv has_subtasks(task: Task) -> bool {
    return len([task->:Splits:->]) > 0;
}


"""Service health plus what this deployment can do. Callable without a login."""
def:pub service_status -> StatusView {
    return StatusView(
        ok=True,
        server_date=today_iso(),
        ai_enabled=ai_available(),
        ai_model=ai_model_name() if ai_available() else "",
        signed_in=len([root-->][?:Profile]) > 0,
        courses=len([root-->][?:Course]),
        open_tasks=len([t for t in all_tasks() if not t.done]),
        goals=len([root-->][?:Goal])
    );
}


"""The caller's planner settings."""
def:protect me -> ProfileView {
    settings = profile_node();
    return ProfileView(
        display_name=settings.display_name,
        daily_capacity_minutes=settings.daily_capacity_minutes,
        day_start_min=settings.day_start_min,
        day_end_min=settings.day_end_min,
        created_at=settings.created_at
    );
}


"""Update planner settings. Any argument left at its default is untouched."""
def:protect update_profile(
    display_name: str = "",
    daily_capacity_minutes: int = 0,
    day_start_min: int = -1,
    day_end_min: int = -1
) -> ProfileView {
    settings = profile_node();
    if display_name {
        settings.display_name = clean_text(display_name, 60);
    }
    if daily_capacity_minutes > 0 {
        settings.daily_capacity_minutes = min(960, daily_capacity_minutes);
    }
    if day_start_min >= 0 {
        settings.day_start_min = min(1380, day_start_min);
    }
    if day_end_min >= 0 {
        settings.day_end_min = min(1439, day_end_min);
    }
    if settings.day_end_min <= settings.day_start_min {
        settings.day_end_min = min(1439, settings.day_start_min + 240);
    }
    return me();
}


"""Today's screen: buckets, blocks, goals and the briefing, in one call."""
def:protect agenda(date: str = "") -> AgendaView {
    target = normalize_date(date) or today_iso();
    return (root spawn Agenda(date=target)).result;
}


"""A week of work bucketed by due date.

`week_offset` steps whole weeks from the anchor, so a client can page back
and forth without owning any calendar arithmetic of its own.
"""
def:protect outlook(start: str = "", span: int = 7, week_offset: int = 0) -> WeekView {
    anchor = normalize_date(start) or week_start(today_iso());
    begin = shift_days(anchor, 7 * max(-260, min(260, week_offset)));
    return (root spawn Outlook(start=begin, span=max(1, min(31, span)))).result;
}


"""Every course, with its workload rolled up."""
def:protect list_courses -> list[CourseView] {
    today = today_iso();
    return [course_view(c, today) for c in all_courses()];
}


"""Add a course. The colour is chosen from the palette when left blank."""
def:protect add_course(
    code: str, title: str = "", credits: int = 0, color: str = "", term: str = ""
) -> CourseView {
    existing = len([root-->][?:Course]);
    course = (
        root ++> Course(
            code=clean_text(code, 16).upper() or "COURSE",
            title=clean_text(title, 120),
            credits=max(0, min(12, credits)),
            color=clean_text(color, 9) or COURSE_PALETTE[existing % len(COURSE_PALETTE)],
            term=clean_text(term, 24),
            created_at=now_iso()
        )
    ) as Course;
    return course_view(course, today_iso());
}


"""Edit a course in place."""
def:protect update_course(
    course_id: str,
    code: str = "",
    title: str = "",
    credits: int = -1,
    color: str = "",
    term: str = ""
) -> CourseView | None {
    course = course_by_id(course_id);
    if course is None {
        return None;
    }
    if code {
        course.code = clean_text(code, 16).upper();
    }
    if title {
        course.title = clean_text(title, 120);
    }
    if credits >= 0 {
        course.credits = min(12, credits);
    }
    if color {
        course.color = clean_text(color, 9);
    }
    if term {
        course.term = clean_text(term, 24);
    }
    return course_view(course, today_iso());
}


"""Delete a course. Its tasks survive and simply lose their course link."""
def:protect remove_course(course_id: str) -> OpResult {
    course = course_by_id(course_id);
    if course is None {
        return OpResult(ok=False, message="No such course.");
    }
    label = course.code;
    del [edge course->:Assigned:->];
    del course;
    return OpResult(ok=True, message=f"Removed {label}.", id=course_id);
}


"""Tasks, newest deadlines first. Completed work is excluded by default."""
def:protect list_tasks(include_done: bool = False, course_id: str = "") -> list[TaskView] {
    today = today_iso();
    views = [task_view(t, today) for t in all_tasks()];
    if not include_done {
        views = [v for v in views if not v.done];
    }
    if course_id {
        course = course_by_id(course_id);
        wanted = jid(course) if course is not None else course_id;
        views = [v for v in views if v.course_id == wanted];
    }
    return rank(views);
}


"""Add a task with every field spelled out."""
def:protect add_task(
    title: str,
    course_id: str = "",
    due_date: str = "",
    due_time: str = "",
    kind: str = "task",
    priority: str = "medium",
    estimate_minutes: int = 0,
    notes: str = ""
) -> TaskView {
    course = course_by_id(course_id);
    minutes = estimate_minutes if estimate_minutes > 0 else 30;
    task = create_task(
        title,
        notes,
        kind,
        priority,
        due_date,
        due_time,
        minutes,
        course,
        "manual"
    );
    return task_view(task, today_iso());
}


"""A one-line readback of how a capture was understood."""
def:priv describe_parse(view: TaskView) -> str {
    parts: list[str] = [];
    if view.course_code {
        parts.append(view.course_code);
    }
    parts.append(view.kind);
    if view.due_date {
        when = pretty_date(view.due_date);
        parts.append(f"due {when} {view.due_time}".strip());
    } else {
        parts.append("no deadline");
    }
    parts.append(fmt_minutes(view.estimate_minutes));
    parts.append(f"{view.priority} priority");
    return " · ".join(parts);
}


"""Capture a task from one line of natural language.

"EECS 449 project proposal due friday 5pm ~3h urgent" becomes a fully
structured task. A model does the reading when one is configured; otherwise
the regex-and-cue parser in `core/ai.jac` handles it, and the result says
which path ran.
"""
def:protect quick_add(capture: str) -> QuickAddResult {
    text = clean_text(capture, 400);
    if not text {
        return QuickAddResult(interpreted="Nothing to add.", ai=False);
    }
    today = today_iso();
    reading = interpret(
        text, today, weekday_name(today), [c.code for c in all_courses()]
    );
    parsed = reading.parsed;
    task = create_task(
        parsed.title,
        "",
        kind_name(parsed.kind),
        priority_name(parsed.priority),
        parsed.due_date,
        parsed.due_time,
        parsed.estimate_minutes,
        course_by_id(parsed.course_code),
        "ai" if reading.ai else "parsed"
    );
    view = task_view(task, today);
    return QuickAddResult(task=view, interpreted=describe_parse(view), ai=reading.ai);
}


"""Edit a task. Arguments left at their defaults are not touched."""
def:protect update_task(
    task_id: str,
    title: str = "",
    notes: str = "",
    kind: str = "",
    priority: str = "",
    due_date: str = "",
    due_time: str = "",
    estimate_minutes: int = 0,
    course_id: str = "",
    clear_due: bool = False,
    clear_course: bool = False
) -> TaskView | None {
    task = task_by_id(task_id);
    if task is None {
        return None;
    }
    if title {
        task.title = clean_text(title, MAX_TITLE);
    }
    if notes {
        task.notes = clean_text(notes, MAX_NOTES);
    }
    if kind {
        task.kind = clean_kind(kind);
    }
    if priority {
        task.priority = clean_priority(priority);
    }
    if due_date {
        task.due_date = normalize_date(due_date);
    }
    if due_time {
        task.due_time = clean_text(due_time, 5);
    }
    if clear_due {
        task.due_date = "";
        task.due_time = "";
    }
    if estimate_minutes > 0 {
        task.estimate_minutes = min(1440, estimate_minutes);
    }
    if clear_course {
        assign_course(task, None);
    } elif course_id {
        assign_course(task, course_by_id(course_id));
    }
    return task_view(task, today_iso());
}


"""Tick or untick a task."""
def:protect set_task_done(task_id: str, done: bool = True) -> TaskView | None {
    task = task_by_id(task_id);
    if task is None {
        return None;
    }
    task.done = done;
    task.done_at = now_iso() if done else "";
    return task_view(task, today_iso());
}


"""Flip a task's completion state and return it."""
def:protect toggle_task(task_id: str) -> TaskView | None {
    task = task_by_id(task_id);
    if task is None {
        return None;
    }
    return set_task_done(task_id, not task.done);
}


"""Delete a task and any subtasks underneath it."""
def:protect remove_task(task_id: str) -> OpResult {
    task = task_by_id(task_id);
    if task is None {
        return OpResult(ok=False, message="No such task.");
    }
    label = task.title;
    for child in [task->:Splits:->] {
        del child;
    }
    del task;
    return OpResult(ok=True, message=f"Deleted \"{label}\".", id=task_id);
}


"""Split a large task into scheduled work sessions underneath it."""
def:protect breakdown_task(task_id: str) -> BreakdownResult {
    task = task_by_id(task_id);
    if task is None {
        return BreakdownResult();
    }
    today = today_iso();
    if has_subtasks(task) {
        return BreakdownResult(
            parent=task_view(task, today),
            subtasks=[task_view(c, today) for c in [task->:Splits:->]],
            ai=False
        );
    }
    course = course_of(task);
    gap = days_until(task, today);
    lead = 0 if gap == NO_DUE_DATE or gap < 0 else gap;
    plan = breakdown(
        task.title,
        task.notes,
        course.code if course is not None else "",
        task.estimate_minutes,
        lead
    );
    steps = plan.subtasks;
    made: list[TaskView] = [];
    for (index, step) in enumerate(steps) {
        # Space the sessions out across the runway so the last one lands on
        # the deadline rather than all of them piling onto it.
        offset = 0;
        if lead > 0 and len(steps) > 1 {
            offset = lead - int(round(float(lead) * float(index) / float(len(steps) - 1)));
        }
        child = create_task(
            step.title,
            "",
            task.kind,
            task.priority,
            shift_days(today, lead - offset) if task.due_date else "",
            "",
            step.estimate_minutes,
            course,
            "breakdown"
        );
        task +>: Splits() :+> child;
        made.append(task_view(child, today));
    }
    return BreakdownResult(parent=task_view(task, today), subtasks=made, ai=plan.ai);
}


"""Read back a stored day plan."""
def:protect get_day_plan(date: str = "") -> PlanResult {
    target = normalize_date(date) or today_iso();
    plan = plan_by_date(target);
    if plan is None {
        return PlanResult(date=target, summary="No plan for this day yet.");
    }
    blocks = sorted([block_view(b, target) for b in [plan->:Scheduled:->]], key=block_sort_key);
    return PlanResult(
        date=target,
        blocks=blocks,
        summary=plan.summary,
        planned_minutes=focus_minutes(blocks),
        ai=plan.ai
    );
}


"""Build a time-blocked schedule for a day and store it.

The candidate pool is everything overdue, due inside a week, or undated --
minus any task that has already been broken down, because its children are
the real work. Ordering comes from the same `urgency` score every client
displays, so the schedule never disagrees with the list above it.
"""
def:protect plan_day(date: str = "", available_minutes: int = 0) -> PlanResult {
    settings = profile_node();
    target = normalize_date(date) or today_iso();
    budget = available_minutes if available_minutes > 0 else settings.daily_capacity_minutes;
    pool: list[TaskView] = [];
    for task in all_tasks() {
        if task.done or has_subtasks(task) {
            continue;
        }
        view = task_view(task, target);
        if view.days_until == NO_DUE_DATE or view.days_until <= 7 {
            pool.append(view);
        }
    }
    (blocks, unplanned) = schedule_day(
        pool, target, settings.day_start_min, settings.day_end_min, budget
    );
    summary = plan_summary(blocks, unplanned);
    existing = plan_by_date(target);
    if existing is not None {
        for stale in [existing->:Scheduled:->] {
            del stale;
        }
        del existing;
    }
    plan = (
        root ++> DayPlan(date=target, summary=summary, ai=False, created_at=now_iso())
    ) as DayPlan;
    for slot in blocks {
        plan +>: Scheduled() :+> Block(
            label=slot.label,
            start_min=slot.start_min,
            end_min=slot.end_min,
            task_id=slot.task_id,
            kind=slot.kind,
            rationale=slot.rationale
        );
    }
    stored = sorted(
        [block_view(b, target) for b in [plan->:Scheduled:->]], key=block_sort_key
    );
    return PlanResult(
        date=target,
        blocks=stored,
        unplanned=unplanned,
        summary=summary,
        planned_minutes=focus_minutes(stored),
        ai=False
    );
}


"""Throw away a stored day plan."""
def:protect clear_day_plan(date: str = "") -> OpResult {
    target = normalize_date(date) or today_iso();
    plan = plan_by_date(target);
    if plan is None {
        return OpResult(ok=False, message="No plan to clear.");
    }
    for stale in [plan->:Scheduled:->] {
        del stale;
    }
    del plan;
    return OpResult(ok=True, message=f"Cleared the plan for {pretty_date(target)}.");
}


"""Every habit with its current streak."""
def:protect list_goals -> list[GoalView] {
    today = today_iso();
    return sorted([goal_view(g, today) for g in all_goals()], key=goal_sort_key);
}


"""Add a habit to track."""
def:protect add_goal(
    title: str, cadence: str = "daily", target_per_period: int = 1, color: str = ""
) -> GoalView {
    rhythm = "weekly" if (cadence or "").strip().lower().startswith("w") else "daily";
    existing = len([root-->][?:Goal]);
    goal = (
        root ++> Goal(
            title=clean_text(title, 80) or "Untitled habit",
            cadence=rhythm,
            target_per_period=max(1, min(20, target_per_period)),
            color=clean_text(color, 9) or COURSE_PALETTE[
                (existing + 3) % len(COURSE_PALETTE)
            ],
            created_at=now_iso()
        )
    ) as Goal;
    return goal_view(goal, today_iso());
}


"""Record that a habit was met on a date."""
def:protect log_goal(goal_id: str, date: str = "") -> GoalView | None {
    goal = goal_by_id(goal_id);
    if goal is None {
        return None;
    }
    when = normalize_date(date) or today_iso();
    goal +>: Logged() :+> Checkin(date=when, created_at=now_iso());
    return goal_view(goal, today_iso());
}


"""Remove the most recent check-in for a date."""
def:protect unlog_goal(goal_id: str, date: str = "") -> GoalView | None {
    goal = goal_by_id(goal_id);
    if goal is None {
        return None;
    }
    when = normalize_date(date) or today_iso();
    for logged in [goal->:Logged:->] {
        if logged.date == when {
            del logged;
            break;
        }
    }
    return goal_view(goal, today_iso());
}


"""Delete a habit and its history."""
def:protect remove_goal(goal_id: str) -> OpResult {
    goal = goal_by_id(goal_id);
    if goal is None {
        return OpResult(ok=False, message="No such habit.");
    }
    label = goal.title;
    for logged in [goal->:Logged:->] {
        del logged;
    }
    del goal;
    return OpResult(ok=True, message=f"Removed \"{label}\".", id=goal_id);
}


"""Fill an empty account with a believable term so the app can be explored.

Refuses to run when the account already holds data, so it can never clobber
real planning.
"""
def:protect seed_demo -> OpResult {
    if all_courses() or all_tasks() {
        return OpResult(
            ok=False, message="This account already has data -- nothing was seeded."
        );
    }
    today = today_iso();
    settings = profile_node();
    settings.display_name = settings.display_name or "Student";
    catalog: list[tuple[str, str, int]] = [
        ("EECS 449", "Conversational Artificial Intelligence", 4),
        ("EECS 485", "Web Systems", 4),
        ("EECS 445", "Introduction to Machine Learning", 4),
        ("STATS 415", "Data Mining and Statistical Learning", 4)
    ];
    made: dict[str, Course] = {};
    for (index, (code, title, credits)) in enumerate(catalog) {
        course = (
            root ++> Course(
                code=code,
                title=title,
                credits=credits,
                color=COURSE_PALETTE[index % len(COURSE_PALETTE)],
                term="Fall 2026",
                created_at=now_iso()
            )
        ) as Course;
        made[code] = course;
    }
    plan: list[tuple[str, str, str, str, int, int]] = [
        ("EECS 449", "Extra credit: full-stack Jac planner", "project", "critical", 5, 300),
        ("EECS 449", "Read the byLLM chapter before lecture", "reading", "medium", 1, 45),
        ("EECS 485", "Project 3: client-side dynamic pages", "assignment", "high", 3, 240),
        ("EECS 485", "Fix the flaky pagination test", "assignment", "medium", -1, 45),
        ("EECS 445", "Problem set 4: SVMs and kernels", "assignment", "high", 2, 180),
        ("EECS 445", "Midterm 1", "exam", "critical", 9, 300),
        ("STATS 415", "Lab writeup: regression diagnostics", "assignment", "medium", 4, 90),
        ("STATS 415", "Reading: chapters 6-7", "reading", "low", 6, 60),
        ("", "Email advisor about winter registration", "admin", "high", 0, 15),
        ("", "Groceries and meal prep", "personal", "low", 1, 60)
    ];
    for (code, title, kind, priority, offset, minutes) in plan {
        create_task(
            title,
            "",
            kind,
            priority,
            shift_days(today, offset),
            "23:59" if kind == "assignment" else "",
            minutes,
            made.get(code),
            "seed"
        );
    }
    habits: list[tuple[str, str, int]] = [
        ("Move for 30 minutes", "daily", 1),
        ("Read something not assigned", "daily", 1),
        ("Office hours", "weekly", 2)
    ];
    for (index, (title, cadence, target)) in enumerate(habits) {
        goal = (
            root ++> Goal(
                title=title,
                cadence=cadence,
                target_per_period=target,
                color=COURSE_PALETTE[(index + 4) % len(COURSE_PALETTE)],
                created_at=now_iso()
            )
        ) as Goal;
        streak = 4 if cadence == "daily" else 0;
        for back in range(1, streak + 1) {
            goal +>: Logged() :+> Checkin(
                date=shift_days(today, -back), created_at=now_iso()
            );
        }
    }
    return OpResult(
        ok=True,
        message=f"Seeded {len(catalog)} courses, {len(plan)} tasks and {len(habits)} habits."
    );
}


"""Erase every planner node under the caller's root. Settings survive."""
def:protect reset_all -> OpResult {
    removed = 0;
    for plan in [root-->][?:DayPlan] {
        for slot in [plan->:Scheduled:->] {
            del slot;
        }
        del plan;
        removed += 1;
    }
    for goal in all_goals() {
        for logged in [goal->:Logged:->] {
            del logged;
        }
        del goal;
        removed += 1;
    }
    for task in all_tasks() {
        del task;
        removed += 1;
    }
    for course in all_courses() {
        del course;
        removed += 1;
    }
    return OpResult(ok=True, message=f"Removed {removed} records.");
}
