"""Rendering and lookup helpers -- no server, no network."""

import from core.contracts { NO_DUE_DATE, TaskView }


def:priv task(ident: str, title: str) -> TaskView {
    return TaskView(id=ident, title=title);
}

test "fit pads short text and truncates long text to an exact width" {
    assert fit("abc", 6) == "abc   ";
    assert len(fit("a much longer piece of text", 10)) == 10;
    assert fit("exactly10!", 10) == "exactly10!";
}

test "durations are compact enough for a terminal column" {
    assert duration(0) == "0m";
    assert duration(45) == "45m";
    assert duration(60) == "1h";
    assert duration(150) == "2h30m";
}

test "clock renders minutes-from-midnight as 24-hour time" {
    assert clock(0) == "00:00";
    assert clock(540) == "09:00";
    assert clock(1439) == "23:59";
}

test "short ids are six characters, which is what the CLI prints" {
    assert short_id("eac3af6aff9347fe8c28370f125e20e2") == "eac3af";
    assert short_id("abc") == "abc";
}

test "colour is suppressed when stdout is not a terminal" {
    # The test runner captures stdout, so paint() must be a no-op here.
    assert paint("hello", BOLD) == "hello";
}

test "a task resolves by full id, by id prefix, or by title" {
    tasks = [
        task("aaaa1111", "Fix the flaky pagination test"),
        task("bbbb2222", "Write the project proposal"),
        task("cccc3333", "Read chapter 7")
    ];
    by_id = resolve_task("aaaa1111", tasks);
    by_prefix = resolve_task("bbbb", tasks);
    by_title = resolve_task("pagination", tasks);
    case_free = resolve_task("CHAPTER", tasks);
    assert by_id is not None and by_id.title == "Fix the flaky pagination test";
    assert by_prefix is not None and by_prefix.title == "Write the project proposal";
    assert by_title is not None and by_title.id == "aaaa1111";
    assert case_free is not None and case_free.id == "cccc3333";
}

test "an ambiguous or missing handle resolves to nothing" {
    tasks = [
        task("aaaa1111", "Read chapter 6"),
        task("aaaa2222", "Read chapter 7")
    ];
    assert resolve_task("aaaa", tasks) is None;
    assert resolve_task("read chapter", tasks) is None;
    assert resolve_task("nothing like this", tasks) is None;
    assert resolve_task("", tasks) is None;
    assert resolve_task("aaaa1111", tasks) is not None;
}

test "deadline text names the urgency a student would feel" {
    assert "overdue 2d" in due_text(TaskView(days_until=-2));
    assert "today" in due_text(TaskView(days_until=0));
    assert "tomorrow" in due_text(TaskView(days_until=1));
    assert "in 5d" in due_text(TaskView(days_until=5));
    assert "someday" in due_text(TaskView(days_until=NO_DUE_DATE));
}

test "a task line is one row holding every column the user reads" {
    line = task_line(
        TaskView(
            id="abcdef0123456789",
            title="Write the project proposal",
            course_code="EECS 449",
            priority="critical",
            estimate_minutes=180,
            days_until=2
        )
    );
    assert "abcdef" in line;
    assert "EECS 449" in line;
    assert "Write the project proposal" in line;
    assert "in 2d" in line;
    assert "3h" in line;
    assert "critical" in line;
    assert "\n" not in line;
}

test "a session round-trips through its file" {
    import os;
    import tempfile;
    with tempfile.TemporaryDirectory() as folder {
        os.environ["ARBOR_HOME"] = folder;
        os.environ.pop("ARBOR_TOKEN", None);
        os.environ.pop("ARBOR_SERVER", None);
        save_session(Session(server="http://example.test", token="abc", username="hunter"));
        restored = load_session();
        assert restored.server == "http://example.test";
        assert restored.token == "abc";
        assert restored.username == "hunter";
        clear_session();
        assert load_session().token == "";
        os.environ.pop("ARBOR_HOME", None);
    }
}
