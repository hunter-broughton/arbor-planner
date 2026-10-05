"""One task row. Presentational -- the parent owns the state and the calls."""

import from core.contracts { TaskView }
import from web.fmt { due_class, due_label, duration, priority_class }


def:pub TaskRow(
    task: TaskView,
    onToggle: Callable[[], None],
    onDelete: Callable[[], None],
    onBreakdown: Callable[[], None],
    pending: bool = False,
    busy: bool = False
) -> JsxElement {
    # While a toggle is in flight, show the state the user asked for. The
    # next refresh either confirms it or quietly puts it back.
    done = task.done != pending;
    rowClass = "task";
    if done {
        rowClass += " is-done";
    }
    if task.parent_id {
        rowClass += " is-sub";
    }
    return
        <div className={rowClass}>
            <button
                className={"task-check is-done" if done else "task-check"}
                onClick={onToggle}
                aria-label="Toggle complete"
            >
                ✓
            </button>
            <div className="task-main">
                <div className="task-title">{task.title}</div>
                <div className="task-meta">
                    {(
                        <span className="course-chip" style={{"color": task.course_color}}>
                            <span
                                className="dot"
                                style={{"backgroundColor": task.course_color}}
                            />
                            {task.course_code}
                        </span>
                    ) if task.course_code else None}
                    <span className={due_class(task)}>{due_label(task)}</span>
                    <span className={priority_class(task.priority)}>{task.priority}</span>
                    <span className="faint">{task.kind}</span>
                    <span className="faint tabular">
                        {duration(task.estimate_minutes)}
                    </span>
                    {(
                        <span className="pill pill-accent">ai</span>
                    ) if task.origin == "ai" else None}
                </div>
            </div>
            <div className="task-actions">
                {(
                    <button
                        className="btn btn-ghost btn-sm"
                        onClick={onBreakdown}
                        disabled={busy}
                        title="Split into work sessions"
                    >
                        Split
                    </button>
                ) if not done and not task.parent_id else None}
                <button className="btn btn-danger btn-sm" onClick={onDelete}>
                    Delete
                </button>
            </div>
        </div>;
}
