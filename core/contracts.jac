"""Wire contracts shared by every Arbor app.

This module is pure data: enums and `obj` views, no nodes, no edges, no
Python imports. That matters because an app may not import another app's
node or edge (E5108) -- only exposed functions, walkers, objs and enums cross
an app boundary. Keeping every cross-boundary payload here means the browser
bundle, the React Native bundle, the CLI and the `planner` service all agree
on one definition of a task, and the type checker enforces it in all four.
"""

glob:pub NO_DUE_DATE: int = 9999;

obj CourseView {
    """A course the planner tracks, with its live workload rolled up."""

    has id: str = "",
        code: str = "",
        title: str = "",
        credits: int = 0,
        color: str = "#0f766e",
        term: str = "",
        open_tasks: int = 0,
        open_minutes: int = 0,
        overdue: int = 0,
        due_this_week: int = 0;
}

obj TaskView {
    """One unit of work, denormalized for display.

    `days_until` is `NO_DUE_DATE` when the task has no deadline, negative when
    it is overdue. `urgency` is the server's ranking score -- the same number
    the day planner sorts by -- so every client orders work identically
    without reimplementing the rule.
    """

    has id: str = "",
        title: str = "",
        notes: str = "",
        kind: str = "task",
        priority: str = "medium",
        due_date: str = "",
        due_time: str = "",
        estimate_minutes: int = 30,
        done: bool = False,
        done_at: str = "",
        created_at: str = "",
        course_id: str = "",
        course_code: str = "",
        course_color: str = "#64748b",
        parent_id: str = "",
        origin: str = "manual",
        days_until: int = NO_DUE_DATE,
        urgency: float = 0.0;
}

obj BlockView {
    """A scheduled slot on a day plan. Minutes are offsets from midnight."""

    has id: str = "",
        label: str = "",
        date: str = "",
        start_min: int = 0,
        end_min: int = 0,
        task_id: str = "",
        kind: str = "focus",
        rationale: str = "";
}

obj GoalView {
    """A recurring habit and its current streak."""

    has id: str = "",
        title: str = "",
        cadence: str = "daily",
        target_per_period: int = 1,
        color: str = "#7c3aed",
        streak: int = 0,
        period_count: int = 0,
        done_this_period: bool = False,
        history: list[str] = [],
        active: bool = True;
}

obj AgendaView {
    """Everything the "today" screen needs, in one round trip."""

    has date: str = "",
        weekday: str = "",
        overdue: list[TaskView] = [],
        due_today: list[TaskView] = [],
        upcoming: list[TaskView] = [],
        completed_today: list[TaskView] = [],
        blocks: list[BlockView] = [],
        goals: list[GoalView] = [],
        courses: list[CourseView] = [],
        recent_days: list[str] = [],
        load_minutes: int = 0,
        capacity_minutes: int = 240,
        done_minutes: int = 0,
        headline: str = "",
        advice: str = "",
        ai: bool = False;
}

obj DayBucket {
    """One column of the week view."""

    has date: str = "",
        weekday: str = "",
        is_today: bool = False,
        is_past: bool = False,
        tasks: list[TaskView] = [],
        minutes: int = 0;
}

obj WeekView {
    """Seven buckets plus whatever has no deadline to sit in."""

    has start: str = "",
        days: list[DayBucket] = [],
        undated: list[TaskView] = [],
        overdue: list[TaskView] = [],
        total_minutes: int = 0,
        busiest: str = "";
}

obj PlanResult {
    """The outcome of scheduling a day."""

    has date: str = "",
        blocks: list[BlockView] = [],
        unplanned: list[TaskView] = [],
        summary: str = "",
        planned_minutes: int = 0,
        ai: bool = False;
}

obj QuickAddResult {
    """A natural-language capture, plus how the server read it."""

    has task: TaskView = TaskView(),
        interpreted: str = "",
        ai: bool = False;
}

obj BreakdownResult {
    """Subtasks created underneath a parent task."""

    has parent: TaskView = TaskView(),
        subtasks: list[TaskView] = [],
        ai: bool = False;
}

obj OpResult {
    """A small acknowledgement for mutations with nothing better to return."""

    has ok: bool = True,
        message: str = "",
        id: str = "";
}

obj StatusView {
    """Service health and capability probe -- the CLI's `arbor status`."""

    has ok: bool = True,
        service: str = "arbor-planner",
        server_date: str = "",
        ai_enabled: bool = False,
        ai_model: str = "",
        signed_in: bool = False,
        courses: int = 0,
        open_tasks: int = 0,
        goals: int = 0;
}

obj ProfileView {
    """Per-user planner settings."""

    has display_name: str = "",
        daily_capacity_minutes: int = 240,
        day_start_min: int = 540,
        day_end_min: int = 1320,
        created_at: str = "";
}
