"""Today -- the screen this planner was built for.

Owns the agenda and the day plan, and drives every mutation through the
`planner` service. One `agenda()` call fills the whole left column, because
the walker on the server assembles it in a single pass over the graph.
"""

import from "@jac/runtime" { jacLogout, useNavigate }

import from core.planner {
    AgendaView,
    PlanResult,
    agenda,
    breakdown_task,
    clear_day_plan,
    get_day_plan,
    log_goal,
    plan_day,
    remove_goal,
    remove_task,
    toggle_task,
    unlog_goal
}
import from web.components.Briefing { Briefing }
import from web.components.DayPlanCard { DayPlanCard }
import from web.components.HabitRow { HabitRow }
import from web.components.QuickAdd { QuickAdd }
import from web.components.TaskList { TaskList }
import from web.fmt { duration, is_auth_error, plural }


def:pub page -> JsxPage {
    has today: AgendaView = AgendaView(),
        plan: PlanResult = PlanResult(),
        loading: bool = True,
        planning: bool = False,
        splitting: str = "",
        pending: list[str] = [],
        error: str = "";

    navigate = useNavigate();

    # A stored token the server no longer accepts: drop it and start over,
    # rather than rendering an empty planner.
    def signOut {
        jacLogout();
        navigate("/login", {"replace": True});
    }

    async can with entry {
        await refresh();
    }

    can with entry {
        onPlanKey = lambda { buildPlan(); };
        document.addEventListener("hunterplan:plan", onPlanKey);
        return lambda { document.removeEventListener("hunterplan:plan", onPlanKey); };
    }

    async def refresh {
        nextAgenda: AgendaView = AgendaView();
        nextPlan: PlanResult = PlanResult();
        try {
            nextAgenda = await agenda("");
            nextPlan = await get_day_plan("");
        } except Exception as e {
            loading = False;
            if is_auth_error(e) {
                signOut();
                return;
            }
            error = "Could not reach the planner service.";
            return;
        }
        error = "";
        today = nextAgenda;
        plan = nextPlan;
        loading = False;
    }

    # Optimistic: the box fills the instant it is clicked, and the refresh
    # that follows either confirms it or puts it back.
    async def toggle(taskId: str) {
        pending = pending + [taskId];
        try {
            await toggle_task(taskId);
            await refresh();
        } except Exception {
            error = "Could not update that task.";
        }
        pending = [id for id in pending if id != taskId];
    }

    async def remove(taskId: str) {
        await remove_task(taskId);
        await refresh();
    }

    async def split(taskId: str) {
        splitting = taskId;
        try {
            await breakdown_task(taskId);
        } except Exception {
            splitting = "";
            error = "Could not split that task.";
            return;
        }
        splitting = "";
        await refresh();
    }

    async def buildPlan {
        planning = True;
        try {
            plan = await plan_day("", 0);
        } except Exception {
            planning = False;
            error = "Could not build a plan.";
            return;
        }
        planning = False;
    }

    async def wipePlan {
        await clear_day_plan("");
        plan = PlanResult();
    }

    async def toggleGoal(goalId: str, done: bool) {
        if done {
            await unlog_goal(goalId, "");
        } else {
            await log_goal(goalId, "");
        }
        await refresh();
    }

    async def dropGoal(goalId: str) {
        await remove_goal(goalId);
        await refresh();
    }

    if loading {
        return <div className="empty">Loading your day...</div>;
    }

    openCount = len(today.overdue) + len(today.due_today);
    return
        <div className="stack">
            <div className="page-head">
                <div>
                    <h1 className="page-title">{today.weekday or "Today"}</h1>
                    <p className="page-sub">
                        {today.date + " · " + plural(openCount, "item") + " on deck · " + duration(today.load_minutes) + " of work"}
                    </p>
                </div>
                <div className="row row-wrap">
                    {(
                        <span className="pill pill-ok">
                            {plural(len(today.completed_today), "done") + " today"}
                        </span>
                    ) if len(today.completed_today) > 0 else None}
                </div>
            </div>

            {(<div className="banner banner-error">{error}</div>) if error else None}

            <Briefing agenda={today}/>
            <QuickAdd onAdded={lambda { refresh(); }}/>

            <div className="two-col">
                <div className="stack">
                    {(
                        <TaskList
                            title="Overdue"
                            tasks={today.overdue}
                            emptyText="Nothing overdue."
                            onToggle={toggle}
                            onDelete={remove}
                            onBreakdown={split}
                            pending={pending}
                            tone="pill pill-danger"
                        />
                    ) if len(today.overdue) > 0 else None}
                    <TaskList
                        title="Due today"
                        tasks={today.due_today}
                        emptyText="Nothing due today. Pull something forward from upcoming."
                        onToggle={toggle}
                        onDelete={remove}
                        onBreakdown={split}
                        pending={pending}
                        tone="pill pill-warn"
                    />
                    <TaskList
                        title="Coming up"
                        tasks={today.upcoming}
                        emptyText="The next ten days are clear."
                        onToggle={toggle}
                        onDelete={remove}
                        onBreakdown={split}
                        pending={pending}
                    />
                    {(
                        <TaskList
                            title="Completed today"
                            tasks={today.completed_today}
                            emptyText=""
                            onToggle={toggle}
                            onDelete={remove}
                            onBreakdown={split}
                            pending={pending}
                            tone="pill pill-ok"
                        />
                    ) if len(today.completed_today) > 0 else None}
                </div>

                <div className="stack">
                    <DayPlanCard
                        plan={plan}
                        busy={planning}
                        onPlan={lambda { buildPlan(); }}
                        onClear={lambda { wipePlan(); }}
                    />
                    <section className="card">
                        <div className="card-head">
                            <h2 className="card-title">Habits</h2>
                            <span className="pill">
                                {str(len([g for g in today.goals if g.done_this_period])) + " / " + str(len(today.goals))}
                            </span>
                        </div>
                        <div className="card-body flush">
                            {(
                                <div className="empty">
                                    No habits yet. Add some on the Habits page.
                                </div>
                            ) if len(today.goals) == 0 else (
                                <div>
                                    {[
                                        <HabitRow
                                            key={goal.id}
                                            goal={goal}
                                            days={today.recent_days}
                                            today={today.date}
                                            onToggle={lambda { toggleGoal(goal.id, goal.done_this_period); }}
                                            onDelete={lambda { dropGoal(goal.id); }}
                                        /> for goal in today.goals
                                    ]}
                                </div>
                            )}
                        </div>
                    </section>
                </div>
            </div>
        </div>;
}
