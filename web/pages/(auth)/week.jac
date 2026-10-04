"""Week -- seven columns of upcoming work, plus what has no home yet.

Paging is a server concern: the client tracks a week offset and the
`outlook` endpoint does the calendar arithmetic, so the browser never has to
know how long a month is.
"""

import from core.planner { WeekView, outlook, toggle_task }
import from web.fmt { day_of_month, duration, due_label, plural }


def:pub page -> JsxPage {
    has week: WeekView = WeekView(),
        offset: int = 0,
        loading: bool = True,
        error: str = "";

    async can with entry {
        await load(0);
    }

    async def load(target: int) {
        fresh: WeekView = WeekView();
        loading = True;
        try {
            fresh = await outlook("", 7, target);
        } except Exception {
            loading = False;
            error = "Could not reach the planner service.";
            return;
        }
        error = "";
        week = fresh;
        offset = target;
        loading = False;
    }

    async def toggle(taskId: str) {
        await toggle_task(taskId);
        await load(offset);
    }

    def caption -> str {
        if offset == 0 {
            return "This week";
        }
        if offset == 1 {
            return "Next week";
        }
        if offset == -1 {
            return "Last week";
        }
        return (str(offset) + " weeks out") if offset > 0 else (str(-offset) + " weeks back");
    }

    if loading and not week.days {
        return <div className="empty">Loading your week...</div>;
    }

    return
        <div className="stack">
            <div className="page-head">
                <div>
                    <h1 className="page-title">{caption()}</h1>
                    <p className="page-sub">
                        {"Week of " + week.start + " · " + duration(week.total_minutes) + " of work"}
                        {(" · busiest " + week.busiest) if week.busiest else ""}
                    </p>
                </div>
                <div className="row">
                    <button className="btn btn-sm" onClick={lambda { load(offset - 1); }}>
                        ← Previous
                    </button>
                    <button
                        className="btn btn-sm"
                        onClick={lambda { load(0); }}
                        disabled={offset == 0}
                    >
                        This week
                    </button>
                    <button className="btn btn-sm" onClick={lambda { load(offset + 1); }}>
                        Next →
                    </button>
                </div>
            </div>

            {(<div className="banner banner-error">{error}</div>) if error else None}

            <div className="week">
                {[
                    <div
                        key={day.date}
                        className={
                            "week-day is-today"
                                if day.is_today
                                else ("week-day is-past" if day.is_past else "week-day")
                        }
                    >
                        <div className="week-head">
                            <div className="week-dow">{day.weekday[:3]}</div>
                            <div className="week-date tabular">
                                {day_of_month(day.date)}
                            </div>
                            <div className="week-load tabular">
                                {duration(day.minutes) if day.minutes > 0 else "—"}
                            </div>
                        </div>
                        <div className="week-body">
                            {[
                                <button
                                    key={task.id}
                                    className="chip"
                                    style={{"borderLeftColor": task.course_color}}
                                    onClick={lambda { toggle(task.id); }}
                                    title="Click to mark complete"
                                >
                                    <span className="chip-title">{task.title}</span>
                                    <span className="chip-meta">
                                        {(task.course_code + " · ") if task.course_code else ""}
                                        {duration(task.estimate_minutes)}
                                    </span>
                                </button> for task in day.tasks
                            ]}
                        </div>
                    </div> for day in week.days
                ]}
            </div>

            <div className="two-col">
                <section className="card">
                    <div className="card-head">
                        <h2 className="card-title">Overdue, outside this window</h2>
                        <span className="pill pill-danger">{str(len(week.overdue))}</span>
                    </div>
                    <div className="card-body flush">
                        {(
                            <div className="empty">Nothing overdue outside this week.</div>
                        ) if len(week.overdue) == 0 else (
                            <div className="task-list">
                                {[
                                    <div key={task.id} className="task">
                                        <div className="task-main">
                                            <div className="task-title">{task.title}</div>
                                            <div className="task-meta">
                                                <span className="pill pill-danger">
                                                    {due_label(task)}
                                                </span>
                                                <span className="faint">{task.due_date}</span>
                                            </div>
                                        </div>
                                    </div> for task in week.overdue
                                ]}
                            </div>
                        )}
                    </div>
                </section>
                <section className="card">
                    <div className="card-head">
                        <h2 className="card-title">No deadline yet</h2>
                        <span className="pill">{str(len(week.undated))}</span>
                    </div>
                    <div className="card-body flush">
                        {(
                            <div className="empty">Everything open has a date on it.</div>
                        ) if len(week.undated) == 0 else (
                            <div className="task-list">
                                {[
                                    <div key={task.id} className="task">
                                        <div className="task-main">
                                            <div className="task-title">{task.title}</div>
                                            <div className="task-meta">
                                                <span className="faint">
                                                    {plural(task.estimate_minutes, "minute")}
                                                </span>
                                                <span className="faint">{task.priority}</span>
                                            </div>
                                        </div>
                                    </div> for task in week.undated
                                ]}
                            </div>
                        )}
                    </div>
                </section>
            </div>
        </div>;
}
