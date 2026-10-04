"""One habit with a 14-day streak strip."""

import from core.contracts { GoalView }


def:pub HabitRow(
    goal: GoalView,
    days: list[str],
    today: str,
    onToggle: Callable[[], None],
    onDelete: Callable[[], None]
) -> JsxElement {
    return
        <div className="habit">
            <button
                className={"task-check is-done" if goal.done_this_period else "task-check"}
                onClick={onToggle}
                aria-label="Toggle habit"
            >
                ✓
            </button>
            <div className="habit-main">
                <div className="habit-title">{goal.title}</div>
                <div className="task-meta">
                    <span className={"pill pill-ok" if goal.streak > 0 else "pill"}>
                        {str(goal.streak) + " " + goal.cadence[:-2] + " streak"}
                    </span>
                    <span className="faint">
                        {str(goal.period_count) + " / " + str(goal.target_per_period) + " this " + ("week" if goal.cadence == "weekly" else "day")}
                    </span>
                </div>
                <div className="streak">
                    {[
                        <div
                            key={day}
                            className={
                                "streak-cell is-hit is-today"
                                    if day in goal.history and day == today
                                    else (
                                        "streak-cell is-hit"
                                            if day in goal.history
                                            else (
                                                "streak-cell is-today"
                                                    if day == today
                                                    else "streak-cell"
                                            )
                                    )
                            }
                            style={{"backgroundColor": goal.color} if day in goal.history else {}}
                            title={day}
                        /> for day in days
                    ]}
                </div>
            </div>
            <button className="btn btn-danger btn-sm" onClick={onDelete}>Delete</button>
        </div>;
}
