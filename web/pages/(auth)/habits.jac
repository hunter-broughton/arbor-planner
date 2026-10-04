"""Habits -- daily and weekly streaks.

Reads the agenda rather than a bespoke endpoint: the walker already returns
every goal with its streak computed and the fourteen-day window resolved, so
there is nothing left for this page to work out.
"""

import from core.planner {
    AgendaView,
    add_goal,
    agenda,
    log_goal,
    remove_goal,
    unlog_goal
}
import from web.components.HabitRow { HabitRow }


def:pub page -> JsxPage {
    has day: AgendaView = AgendaView(),
        title: str = "",
        cadence: str = "daily",
        target: str = "1",
        loading: bool = True,
        adding: bool = False,
        error: str = "";

    async can with entry {
        await load();
    }

    async def load {
        fresh: AgendaView = AgendaView();
        try {
            fresh = await agenda("");
        } except Exception {
            loading = False;
            error = "Could not reach the planner service.";
            return;
        }
        error = "";
        day = fresh;
        loading = False;
    }

    async def create {
        if not title.strip() or adding {
            return;
        }
        adding = True;
        try {
            await add_goal(title.strip(), cadence, parseTarget(), "");
        } except Exception {
            adding = False;
            error = "Could not add that habit.";
            return;
        }
        adding = False;
        title = "";
        target = "1";
        await load();
    }

    def parseTarget -> int {
        try {
            return max(1, int(target));
        } except Exception {
            return 1;
        }
    }

    async def toggle(goalId: str, done: bool) {
        if done {
            await unlog_goal(goalId, "");
        } else {
            await log_goal(goalId, "");
        }
        await load();
    }

    async def drop(goalId: str) {
        await remove_goal(goalId);
        await load();
    }

    if loading {
        return <div className="empty">Loading your habits...</div>;
    }

    kept = len([g for g in day.goals if g.done_this_period]);
    best = max([g.streak for g in day.goals]) if day.goals else 0;
    return
        <div className="stack">
            <div className="page-head">
                <div>
                    <h1 className="page-title">Habits</h1>
                    <p className="page-sub">
                        {str(kept) + " of " + str(len(day.goals)) + " kept this period · longest streak " + str(best)}
                    </p>
                </div>
            </div>

            {(<div className="banner banner-error">{error}</div>) if error else None}

            <section className="card">
                <div className="card-body">
                    <div className="row row-wrap">
                        <div className="field grow">
                            <label className="field-label">Habit</label>
                            <input
                                className="input"
                                value={title}
                                placeholder="Move for 30 minutes"
                                onChange={lambda (e: ChangeEvent) { title = e.target.value; }}
                                onKeyDown={lambda (e: KeyboardEvent) {
                                    if e.key == "Enter" { create(); }
                                }}
                            />
                        </div>
                        <div className="field" style={{"width": "128px"}}>
                            <label className="field-label">Cadence</label>
                            <select
                                className="select"
                                value={cadence}
                                onChange={lambda (e: ChangeEvent) { cadence = e.target.value; }}
                            >
                                <option value="daily">Daily</option>
                                <option value="weekly">Weekly</option>
                            </select>
                        </div>
                        <div className="field" style={{"width": "92px"}}>
                            <label className="field-label">Target</label>
                            <input
                                className="input tabular"
                                value={target}
                                onChange={lambda (e: ChangeEvent) { target = e.target.value; }}
                            />
                        </div>
                        <button
                            className="btn btn-primary"
                            onClick={lambda { create(); }}
                            disabled={adding}
                            style={{"alignSelf": "flex-end"}}
                        >
                            Add habit
                        </button>
                    </div>
                    <div className="field-hint" style={{"marginTop": "8px"}}>
                        A weekly habit with a target of 2 counts as kept once you
                        check it twice in the same calendar week.
                    </div>
                </div>
            </section>

            <section className="card">
                <div className="card-head">
                    <h2 className="card-title">Tracking</h2>
                    <span className="pill">{str(len(day.goals))}</span>
                </div>
                <div className="card-body flush">
                    {(
                        <div className="empty">
                            Nothing tracked yet. Add a habit above.
                        </div>
                    ) if len(day.goals) == 0 else (
                        <div>
                            {[
                                <HabitRow
                                    key={goal.id}
                                    goal={goal}
                                    days={day.recent_days}
                                    today={day.date}
                                    onToggle={lambda { toggle(goal.id, goal.done_this_period); }}
                                    onDelete={lambda { drop(goal.id); }}
                                /> for goal in day.goals
                            ]}
                        </div>
                    )}
                </div>
            </section>
        </div>;
}
