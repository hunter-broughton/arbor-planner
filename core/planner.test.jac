"""Graph-level behaviour of the planner service.

`jac test` runs blocks in parallel against a root that persists between
runs, so every test here tags the nodes it creates with a unique marker,
asserts only on those, and deletes them again.
"""

import from core.timeutil { shift_days, today_iso }


"""Delete a task and anything hanging under it."""
def:priv scrub(task: Task) {
    for child in [task->:Splits:->] {
        del child;
    }
    del task;
}

test "a created task carries its course, its deadline and a score" {
    today = today_iso();
    course = (root ++> Course(code="TEST 101", title="Fixtures")) as Course;
    task = create_task(
        "marker-basic write the thing",
        "notes here",
        "pset",
        "URGENT",
        shift_days(today, 2),
        "17:00",
        120,
        course,
        "manual"
    );
    view = task_view(task, today);
    assert view.title == "marker-basic write the thing";
    assert view.course_code == "TEST 101";
    assert view.course_id == jid(course);
    assert view.kind == "assignment";
    assert view.priority == "critical";
    assert view.days_until == 2;
    assert view.estimate_minutes == 120;
    assert view.urgency > 0.0;
    assert not view.done;
    scrub(task);
    del course;
}

test "field values are cleaned and clamped on the way in" {
    task = create_task(
        "  marker-clean  ", "", "nonsense", "", "not a date", "", 99999, None, "manual"
    );
    view = task_view(task, today_iso());
    assert view.title == "marker-clean";
    assert view.kind == "task";
    assert view.priority == "medium";
    assert view.due_date == "";
    assert view.estimate_minutes == 1440;
    assert view.days_until == NO_DUE_DATE;
    scrub(task);
}

test "reassigning a course replaces the link rather than stacking them" {
    first = (root ++> Course(code="TEST 201")) as Course;
    second = (root ++> Course(code="TEST 202")) as Course;
    task = create_task("marker-move", "", "task", "medium", "", "", 30, first, "manual");
    assert len([task<-:Assigned:<-]) == 1;
    assign_course(task, second);
    owners = [task<-:Assigned:<-];
    assert len(owners) == 1;
    assert owners[0].code == "TEST 202";
    assign_course(task, None);
    assert len([task<-:Assigned:<-]) == 0;
    assert course_of(task) is None;
    scrub(task);
    del first;
    del second;
}

test "a course rolls up only its own open workload" {
    today = today_iso();
    course = (root ++> Course(code="TEST 301")) as Course;
    open_one = create_task(
        "marker-load a", "", "assignment", "high", shift_days(today, 1), "", 60, course, "manual"
    );
    open_two = create_task(
        "marker-load b", "", "assignment", "high", shift_days(today, -1), "", 30, course, "manual"
    );
    finished = create_task(
        "marker-load c", "", "assignment", "high", today, "", 90, course, "manual"
    );
    finished.done = True;
    view = course_view(course, today);
    assert view.open_tasks == 2;
    assert view.open_minutes == 90;
    assert view.overdue == 1;
    assert view.due_this_week == 1;
    scrub(open_one);
    scrub(open_two);
    scrub(finished);
    del course;
}

test "a daily streak counts back from today and stops at the first gap" {
    today = today_iso();
    goal = (root ++> Goal(title="marker-streak", cadence="daily")) as Goal;
    for back in [0, 1, 2, 4] {
        goal +>: Logged() :+> Checkin(date=shift_days(today, -back));
    }
    view = goal_view(goal, today);
    assert view.streak == 3;
    assert view.done_this_period;
    assert view.period_count == 1;
    for logged in [goal->:Logged:->] {
        del logged;
    }
    del goal;
}

test "an unfinished today does not break yesterday's streak" {
    today = today_iso();
    goal = (root ++> Goal(title="marker-pending", cadence="daily")) as Goal;
    for back in [1, 2, 3] {
        goal +>: Logged() :+> Checkin(date=shift_days(today, -back));
    }
    view = goal_view(goal, today);
    assert view.streak == 3;
    assert not view.done_this_period;
    for logged in [goal->:Logged:->] {
        del logged;
    }
    del goal;
}

test "a weekly goal needs its target before the week counts" {
    today = today_iso();
    goal = (
        root ++> Goal(title="marker-weekly", cadence="weekly", target_per_period=2)
    ) as Goal;
    goal +>: Logged() :+> Checkin(date=today);
    assert not goal_view(goal, today).done_this_period;
    goal +>: Logged() :+> Checkin(date=today);
    assert goal_view(goal, today).done_this_period;
    for logged in [goal->:Logged:->] {
        del logged;
    }
    del goal;
}

test "the Agenda walker reaches a course's task exactly once" {
    today = today_iso();
    course = (root ++> Course(code="TEST 401")) as Course;
    task = create_task(
        "marker-walk", "", "assignment", "high", today, "", 45, course, "manual"
    );
    day = (root spawn Agenda(date=today)).result;
    # Reachable from root AND through its course -- the walker must dedupe.
    hits = [t for t in day.due_today if t.id == jid(task)];
    assert len(hits) == 1;
    assert hits[0].course_code == "TEST 401";
    assert len([c for c in day.courses if c.code == "TEST 401"]) == 1;
    assert day.date == today;
    assert day.weekday != "";
    assert day.headline != "";
    scrub(task);
    del course;
}

test "the week view buckets a task onto its due date" {
    today = today_iso();
    target = shift_days(today, 2);
    task = create_task(
        "marker-week", "", "assignment", "medium", target, "", 60, None, "manual"
    );
    week = (root spawn Outlook(start=today, span=7)).result;
    assert week.start == today;
    assert len(week.days) == 7;
    landed = [
        d for d in week.days if d.date == target and any(
            [t.id == jid(task) for t in d.tasks]
        )
    ];
    assert len(landed) == 1;
    assert landed[0].minutes >= 60;
    scrub(task);
}

test "breaking a task down makes children that point back at it" {
    today = today_iso();
    task = create_task(
        "marker-split", "", "project", "high", shift_days(today, 6), "", 300, None, "manual"
    );
    assert not has_subtasks(task);
    result = breakdown_task(jid(task));
    assert len(result.subtasks) >= 2;
    assert has_subtasks(task);
    for child in result.subtasks {
        assert child.parent_id == jid(task);
    }
    # A second call is idempotent -- it reports the existing children.
    again = breakdown_task(jid(task));
    assert len(again.subtasks) == len(result.subtasks);
    scrub(task);
}
