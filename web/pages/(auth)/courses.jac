"""Courses -- the term at a glance, and what each class is costing you."""

import from "@jac/runtime" { jacLogout, useNavigate }

import from core.planner {
    CourseView,
    TaskView,
    add_course,
    breakdown_task,
    list_courses,
    list_tasks,
    remove_course,
    remove_task,
    toggle_task
}
import from web.components.TaskList { TaskList }
import from web.fmt { duration, is_auth_error }


def:pub page -> JsxPage {
    has courses: list[CourseView] = [],
        tasks: list[TaskView] = [],
        selected: str = "",
        code: str = "",
        title: str = "",
        credits: str = "4",
        adding: bool = False,
        loading: bool = True,
        error: str = "";

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
        freshCourses: list[CourseView] = [];
        freshTasks: list[TaskView] = [];
        try {
            freshCourses = await list_courses();
            freshTasks = await list_tasks(True, "");
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
        courses = freshCourses;
        tasks = freshTasks;
        loading = False;
    }

    async def create {
        if not code.strip() or adding {
            return;
        }
        adding = True;
        try {
            await add_course(code.strip(), title.strip(), parseCredits(), "", "");
        } except Exception {
            adding = False;
            error = "Could not add that course.";
            return;
        }
        adding = False;
        code = "";
        title = "";
        await load();
    }

    def parseCredits -> int {
        try {
            return int(credits);
        } except Exception {
            return 0;
        }
    }

    async def drop(courseId: str) {
        await remove_course(courseId);
        if selected == courseId {
            selected = "";
        }
        await load();
    }

    async def toggle(taskId: str) {
        await toggle_task(taskId);
        await load();
    }

    async def remove(taskId: str) {
        await remove_task(taskId);
        await load();
    }

    async def split(taskId: str) {
        await breakdown_task(taskId);
        await load();
    }

    def tasksFor(courseId: str) -> list[TaskView] {
        return [t for t in tasks if t.course_id == courseId];
    }

    if loading {
        return <div className="empty">Loading your courses...</div>;
    }

    openTotal = sum([c.open_minutes for c in courses]);
    return
        <div className="stack">
            <div className="page-head">
                <div>
                    <h1 className="page-title">Courses</h1>
                    <p className="page-sub">
                        {str(len(courses)) + " tracked · " + duration(openTotal) + " of open work · " + str(sum([c.credits for c in courses])) + " credits"}
                    </p>
                </div>
            </div>

            {(<div className="banner banner-error">{error}</div>) if error else None}

            <section className="card">
                <div className="card-body">
                    <div className="row row-wrap">
                        <div className="field" style={{"width": "140px"}}>
                            <label className="field-label">Code</label>
                            <input
                                className="input"
                                value={code}
                                placeholder="EECS 449"
                                onChange={lambda (e: ChangeEvent) { code = e.target.value; }}
                            />
                        </div>
                        <div className="field grow">
                            <label className="field-label">Title</label>
                            <input
                                className="input"
                                value={title}
                                placeholder="Conversational Artificial Intelligence"
                                onChange={lambda (e: ChangeEvent) { title = e.target.value; }}
                            />
                        </div>
                        <div className="field" style={{"width": "92px"}}>
                            <label className="field-label">Credits</label>
                            <input
                                className="input tabular"
                                value={credits}
                                onChange={lambda (e: ChangeEvent) { credits = e.target.value; }}
                            />
                        </div>
                        <button
                            className="btn btn-primary"
                            onClick={lambda { create(); }}
                            disabled={adding}
                            style={{"alignSelf": "flex-end"}}
                        >
                            Add course
                        </button>
                    </div>
                </div>
            </section>

            {(
                <div className="empty">
                    No courses yet. Add one above, or seed a sample term from
                    Settings.
                </div>
            ) if len(courses) == 0 else (
                <div className="grid-cards">
                    {[
                        <div
                            key={course.id}
                            className="card course-card rise"
                            style={{"--accent-color": course.color}}
                        >
                            <div className="row spread">
                                <div className="row">
                                    <span
                                        className="dot"
                                        style={{"backgroundColor": course.color}}
                                    />
                                    <span className="course-code">{course.code}</span>
                                </div>
                                {(
                                    <span className="pill pill-danger">
                                        {str(course.overdue) + " overdue"}
                                    </span>
                                ) if course.overdue > 0 else None}
                            </div>
                            <div className="course-title">
                                {course.title or "No title"}
                            </div>
                            <div className="course-stats">
                                <div>
                                    <div className="stat-num">
                                        {str(course.open_tasks)}
                                    </div>
                                    <div className="stat-label">open</div>
                                </div>
                                <div>
                                    <div className="stat-num">
                                        {duration(course.open_minutes)}
                                    </div>
                                    <div className="stat-label">workload</div>
                                </div>
                                <div>
                                    <div className="stat-num">
                                        {str(course.due_this_week)}
                                    </div>
                                    <div className="stat-label">this week</div>
                                </div>
                            </div>
                            <div className="row spread">
                                <button
                                    className="btn btn-sm"
                                    onClick={lambda {
                                        selected = "" if selected == course.id else course.id;
                                    }}
                                >
                                    {("Hide tasks" if selected == course.id else "Show tasks")}
                                </button>
                                <button
                                    className="btn btn-danger btn-sm"
                                    onClick={lambda { drop(course.id); }}
                                >
                                    Remove
                                </button>
                            </div>
                        </div> for course in courses
                    ]}
                </div>
            )}

            {(
                <TaskList
                    title={"Tasks"}
                    tasks={tasksFor(selected)}
                    emptyText="Nothing filed under this course yet."
                    onToggle={toggle}
                    onDelete={remove}
                    onBreakdown={split}
                />
            ) if selected else None}
        </div>;
}
