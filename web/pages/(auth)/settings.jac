"""Settings -- working hours, capacity, and the data controls.

Also the honest readout of whether this deployment has an AI provider
configured, since every AI feature has a deterministic twin and the app
behaves identically either way apart from the quality of the prose.
"""

import from "@jac/runtime" { jacLogout, useNavigate }

import from core.planner {
    OpResult,
    ProfileView,
    StatusView,
    me,
    reset_all,
    seed_demo,
    service_status,
    update_profile
}
import from web.fmt { clock, duration, is_auth_error }


def:pub page -> JsxPage {
    has settings: ProfileView = ProfileView(),
        status: StatusView = StatusView(),
        displayName: str = "",
        capacity: str = "240",
        dayStart: str = "09:00",
        dayEnd: str = "22:00",
        notice: str = "",
        error: str = "",
        loading: bool = True,
        saving: bool = False;

    navigate = useNavigate();

    # A stored token the server no longer accepts: drop it and start over,
    # rather than rendering an empty planner.
    def signOut {
        jacLogout();
        navigate("/login", {"replace": True});
    }

    async can with entry {
        await load();
    }

    async def load {
        freshProfile: ProfileView = ProfileView();
        freshStatus: StatusView = StatusView();
        try {
            freshProfile = await me();
            freshStatus = await service_status();
        } except Exception as e {
            loading = False;
            if is_auth_error(e) {
                signOut();
                return;
            }
            error = "Could not reach the planner service.";
            return;
        }
        settings = freshProfile;
        status = freshStatus;
        displayName = freshProfile.display_name;
        capacity = str(freshProfile.daily_capacity_minutes);
        dayStart = toClock(freshProfile.day_start_min);
        dayEnd = toClock(freshProfile.day_end_min);
        loading = False;
    }

    def toClock(minutes: int) -> str {
        hours = minutes // 60;
        mins = minutes % 60;
        return ("0" + str(hours) if hours < 10 else str(hours)) + ":" + ("0" + str(mins) if mins < 10 else str(mins));
    }

    def fromClock(value: str) -> int {
        parts = value.split(":");
        if len(parts) != 2 {
            return -1;
        }
        try {
            return int(parts[0]) * 60 + int(parts[1]);
        } except Exception {
            return -1;
        }
    }

    async def save {
        updated: ProfileView = ProfileView();
        saving = True;
        notice = "";
        try {
            updated = await update_profile(
                displayName, parseCapacity(), fromClock(dayStart), fromClock(dayEnd)
            );
        } except Exception {
            saving = False;
            error = "Could not save those settings.";
            return;
        }
        saving = False;
        error = "";
        settings = updated;
        notice = "Saved.";
    }

    def parseCapacity -> int {
        try {
            return max(0, int(capacity));
        } except Exception {
            return 0;
        }
    }

    async def seed {
        result: OpResult = OpResult();
        try {
            result = await seed_demo();
        } except Exception {
            error = "Could not seed sample data.";
            return;
        }
        notice = result.message;
        await load();
    }

    async def wipe {
        result: OpResult = OpResult();
        try {
            result = await reset_all();
        } except Exception {
            error = "Could not clear your data.";
            return;
        }
        notice = result.message;
        await load();
    }

    if loading {
        return <div className="empty">Loading settings...</div>;
    }

    return
        <div className="stack">
            <div className="page-head">
                <div>
                    <h1 className="page-title">Settings</h1>
                    <p className="page-sub">
                        How HunterPlan plans your day, and what it knows about you.
                    </p>
                </div>
            </div>

            {(<div className="banner banner-error">{error}</div>) if error else None}
            {(<div className="banner banner-ok">{notice}</div>) if notice and not error else None}

            <div className="two-col">
                <section className="card">
                    <div className="card-head">
                        <h2 className="card-title">Planning</h2>
                    </div>
                    <div className="card-body stack">
                        <div className="field">
                            <label className="field-label">Display name</label>
                            <input
                                className="input"
                                value={displayName}
                                placeholder="Your name"
                                onChange={lambda (e: ChangeEvent) { displayName = e.target.value; }}
                            />
                        </div>
                        <div className="field">
                            <label className="field-label">
                                Daily focus capacity (minutes)
                            </label>
                            <input
                                className="input tabular"
                                value={capacity}
                                onChange={lambda (e: ChangeEvent) { capacity = e.target.value; }}
                            />
                            <span className="field-hint">
                                {"Currently " + duration(settings.daily_capacity_minutes) + ". The day planner never schedules past this."}
                            </span>
                        </div>
                        <div className="row">
                            <div className="field grow">
                                <label className="field-label">Day starts</label>
                                <input
                                    className="input tabular"
                                    value={dayStart}
                                    placeholder="09:00"
                                    onChange={lambda (e: ChangeEvent) { dayStart = e.target.value; }}
                                />
                            </div>
                            <div className="field grow">
                                <label className="field-label">Day ends</label>
                                <input
                                    className="input tabular"
                                    value={dayEnd}
                                    placeholder="22:00"
                                    onChange={lambda (e: ChangeEvent) { dayEnd = e.target.value; }}
                                />
                            </div>
                        </div>
                        <span className="field-hint">
                            {"Blocks are laid between " + clock(settings.day_start_min) + " and " + clock(settings.day_end_min) + "."}
                        </span>
                        <div className="row">
                            <button
                                className="btn btn-primary"
                                onClick={lambda { save(); }}
                                disabled={saving}
                            >
                                {("Saving..." if saving else "Save settings")}
                            </button>
                        </div>
                    </div>
                </section>

                <div className="stack">
                    <section className="card">
                        <div className="card-head">
                            <h2 className="card-title">Service</h2>
                        </div>
                        <div className="card-body stack-sm">
                            <div className="row spread">
                                <span className="muted">Planner service</span>
                                <span className="pill pill-ok">reachable</span>
                            </div>
                            <div className="row spread">
                                <span className="muted">Server date</span>
                                <span className="mono">{status.server_date}</span>
                            </div>
                            <div className="row spread">
                                <span className="muted">AI assist</span>
                                <span className={"pill pill-accent" if status.ai_enabled else "pill"}>
                                    {(status.ai_model if status.ai_enabled else "not configured")}
                                </span>
                            </div>
                            <div className="row spread">
                                <span className="muted">Tracked</span>
                                <span className="mono">
                                    {str(status.courses) + " courses · " + str(status.open_tasks) + " open · " + str(status.goals) + " habits"}
                                </span>
                            </div>
                            <div className="field-hint">
                                Without a provider key every AI feature falls back
                                to a deterministic implementation -- capture
                                parsing, task breakdowns and the daily briefing
                                all keep working.
                            </div>
                        </div>
                    </section>

                    <section className="card">
                        <div className="card-head">
                            <h2 className="card-title">Data</h2>
                        </div>
                        <div className="card-body stack-sm">
                            <div className="row spread">
                                <div>
                                    <div>Seed a sample term</div>
                                    <div className="field-hint">
                                        Four courses, ten tasks and three habits.
                                        Refuses to run on an account with data.
                                    </div>
                                </div>
                                <button className="btn btn-sm" onClick={lambda { seed(); }}>
                                    Seed
                                </button>
                            </div>
                            <div className="row spread">
                                <div>
                                    <div>Clear everything</div>
                                    <div className="field-hint">
                                        Deletes all courses, tasks, plans and
                                        habits. Settings survive.
                                    </div>
                                </div>
                                <button
                                    className="btn btn-danger btn-sm"
                                    onClick={lambda { wipe(); }}
                                >
                                    Reset
                                </button>
                            </div>
                        </div>
                    </section>
                </div>
            </div>
        </div>;
}
