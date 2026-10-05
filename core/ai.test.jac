"""The deterministic half of the AI layer.

These run with no model and no key: `heuristic_parse` is what the planner
actually uses when nothing is configured, so it is held to the same standard
as the model path.
"""

glob COURSES: list[str] = ["EECS 449", "EECS 485", "EECS 445", "STATS 415"];

glob TODAY: str = "2026-10-04";


test "a full capture is read apart into every field" {
    parsed = heuristic_parse(
        "EECS 449 project proposal due friday 5pm ~3h urgent", TODAY, COURSES
    );
    assert parsed.title == "Project proposal";
    assert parsed.course_code == "EECS 449";
    assert kind_name(parsed.kind) == "project";
    assert priority_name(parsed.priority) == "critical";
    assert parsed.due_date == "2026-10-09";
    assert parsed.due_time == "17:00";
    assert parsed.estimate_minutes == 180;
}

test "course codes match however they are written" {
    assert heuristic_parse("eecs449 reading", TODAY, COURSES).course_code == "EECS 449";
    assert heuristic_parse("EECS-485 lab", TODAY, COURSES).course_code == "EECS 485";
    assert heuristic_parse("stats 415 homework", TODAY, COURSES).course_code == "STATS 415";
    # A course the student is not enrolled in is not invented.
    assert heuristic_parse("MATH 214 homework", TODAY, COURSES).course_code == "";
}

test "relative deadlines resolve against the given day" {
    assert heuristic_parse("thing today", TODAY, COURSES).due_date == TODAY;
    assert heuristic_parse("thing tomorrow", TODAY, COURSES).due_date == "2026-10-05";
    assert heuristic_parse("thing next week", TODAY, COURSES).due_date == "2026-10-11";
    assert heuristic_parse("thing in 3 days", TODAY, COURSES).due_date == "2026-10-07";
    assert heuristic_parse("thing by 10/9", TODAY, COURSES).due_date == "2026-10-09";
    assert heuristic_parse("thing on 2026-11-02", TODAY, COURSES).due_date == "2026-11-02";
    assert heuristic_parse("thing by oct 20", TODAY, COURSES).due_date == "2026-10-20";
    assert heuristic_parse("some thing", TODAY, COURSES).due_date == "";
}

test "durations are understood in hours and minutes" {
    assert heuristic_parse("task 90m", TODAY, COURSES).estimate_minutes == 90;
    assert heuristic_parse("task 2 hours", TODAY, COURSES).estimate_minutes == 120;
    assert heuristic_parse("task ~1.5h", TODAY, COURSES).estimate_minutes == 90;
    assert heuristic_parse("task 45 min", TODAY, COURSES).estimate_minutes == 45;
}

test "kind is inferred from how students actually talk" {
    assert kind_name(heuristic_parse("pset 4", TODAY, COURSES).kind) == "assignment";
    assert kind_name(heuristic_parse("study for midterm", TODAY, COURSES).kind) == "exam";
    assert kind_name(heuristic_parse("reading chapter 3", TODAY, COURSES).kind) == "reading";
    assert kind_name(heuristic_parse("gym", TODAY, COURSES).kind) == "fitness";
    assert kind_name(heuristic_parse("email advisor", TODAY, COURSES).kind) == "admin";
    # "final exam" is an exam; a "final writeup" is still an assignment.
    assert kind_name(heuristic_parse("final exam", TODAY, COURSES).kind) == "exam";
    assert kind_name(heuristic_parse("final writeup", TODAY, COURSES).kind) == "assignment";
}

test "unstated priority is implied, stated priority is obeyed" {
    assert priority_name(heuristic_parse("quiz tomorrow", TODAY, COURSES).priority) == "high";
    assert priority_name(heuristic_parse("thing in 30 days", TODAY, COURSES).priority) == "medium";
    assert priority_name(heuristic_parse("laundry whenever", TODAY, COURSES).priority) == "low";
    assert priority_name(heuristic_parse("asap thing", TODAY, COURSES).priority) == "critical";
}

test "a title is always produced, even from junk" {
    assert heuristic_parse("", TODAY, COURSES).title == "Untitled task";
    assert heuristic_parse("due by the", TODAY, COURSES).title != "";
    # The structured parts are stripped out of the title.
    title = heuristic_parse("EECS 485 lab 3 due friday 2h high priority", TODAY, COURSES).title;
    assert "friday" not in title.lower();
    assert "EECS" not in title;
    assert "lab 3" in title.lower();
}

test "interpret falls back cleanly when no model is configured" {
    import os;
    os.environ["HUNTERPLAN_NO_AI"] = "1";
    assert not ai_available();
    reading = interpret("pset 4 eecs445 due friday ~2h", TODAY, "Sunday", COURSES);
    assert not reading.ai;
    assert reading.parsed.course_code == "EECS 445";
    os.environ.pop("HUNTERPLAN_NO_AI", None);
}

test "a model's parse is rejected when it will not stand up" {
    good = ParsedTask(title="Write it", due_date="2026-10-09", estimate_minutes=60);
    assert parse_is_usable(good, TODAY, COURSES);
    assert not parse_is_usable(ParsedTask(title="  "), TODAY, COURSES);
    assert not parse_is_usable(
        ParsedTask(title="x", due_date="whenever", estimate_minutes=60), TODAY, COURSES
    );
    # A model that resolved "friday" against the wrong year lands in the past.
    assert not parse_is_usable(
        ParsedTask(title="x", due_date="2025-10-09", estimate_minutes=60), TODAY, COURSES
    );
    # A course the student is not enrolled in.
    assert not parse_is_usable(
        ParsedTask(title="x", course_code="PHIL 101", estimate_minutes=60), TODAY, COURSES
    );
}

test "the fallback breakdown paces work into sessions that add up" {
    steps = heuristic_breakdown(300);
    assert 3 <= len(steps) <= 6;
    assert all([s.estimate_minutes >= 15 for s in steps]);
    total = sum([s.estimate_minutes for s in steps]);
    assert 240 <= total <= 360;
    assert "submit" in steps[-1].title.lower();
}

test "the fallback briefing reacts to the shape of the day" {
    backlog = heuristic_briefing(3, 0, 0, 120, 240, "Pset 4");
    assert "overdue" in backlog.headline;
    assert "Pset 4" in backlog.advice;
    heavy = heuristic_briefing(0, 4, 2, 500, 240, "Project 3");
    assert heavy.headline == "Heavy day ahead";
    clear = heuristic_briefing(0, 0, 0, 0, 240, "");
    assert clear.headline == "All clear";
}
