"""Argument parsing -- the CLI's contract with the person typing."""

test "the parser understands every top-level command" {
    parser = build_parser();
    names = [
        "login",
        "logout",
        "status",
        "today",
        "add",
        "ls",
        "done",
        "undone",
        "rm",
        "split",
        "plan",
        "week",
        "courses",
        "course",
        "habits",
        "habit",
        "check",
        "uncheck",
        "seed",
        "reset"
    ];
    for name in names {
        parsed = parser.parse_args([name] + extra_args_for(name));
        assert text_of(parsed, "command") == name;
    }
}

"""The smallest argument list each command needs to parse."""
def:priv extra_args_for(name: str) -> list[str] {
    if name in ["login"] {
        return ["hunter"];
    }
    if name in ["done", "undone", "rm", "split"] {
        return ["thing"];
    }
    if name in ["check", "uncheck"] {
        return ["gym"];
    }
    if name == "add" {
        return ["something"];
    }
    if name == "course" {
        return ["add", "EECS 449"];
    }
    if name == "habit" {
        return ["add", "run"];
    }
    return [];
}

test "a multi-word capture is rejoined into one line" {
    parsed = build_parser().parse_args(
        ["add", "EECS", "449", "proposal", "due", "friday", "~3h"]
    );
    assert " ".join(getattr(parsed, "text", [])) == "EECS 449 proposal due friday ~3h";
}

test "ls flags map onto the endpoint's parameters" {
    parser = build_parser();
    plain = parser.parse_args(["ls"]);
    assert not flag_of(plain, "include_done");
    assert text_of(plain, "course") == "";
    filtered = parser.parse_args(["ls", "--all", "--course", "EECS 485"]);
    assert flag_of(filtered, "include_done");
    assert text_of(filtered, "course") == "EECS 485";
}

test "plan and week take numeric options with sane defaults" {
    parser = build_parser();
    assert number_of(parser.parse_args(["plan"]), "minutes") == 0;
    assert number_of(parser.parse_args(["plan", "--minutes", "300"]), "minutes") == 300;
    assert flag_of(parser.parse_args(["plan", "--show"]), "show");
    assert flag_of(parser.parse_args(["plan", "--clear"]), "clear");
    assert number_of(parser.parse_args(["week"]), "offset") == 0;
    assert number_of(parser.parse_args(["week", "--offset", "-2"]), "offset") == -2;
}

test "course and habit subcommands carry their action" {
    parser = build_parser();
    added = parser.parse_args(
        ["course", "add", "EECS 449", "--title", "Conversational AI", "--credits", "4"]
    );
    assert text_of(added, "action") == "add";
    assert text_of(added, "code") == "EECS 449";
    assert text_of(added, "title") == "Conversational AI";
    assert number_of(added, "credits") == 4;
    removed = parser.parse_args(["course", "rm", "EECS 449"]);
    assert text_of(removed, "action") == "rm";
    habit = parser.parse_args(["habit", "add", "Move", "daily", "--weekly", "--target", "3"]);
    assert flag_of(habit, "weekly");
    assert number_of(habit, "target", 1) == 3;
    assert " ".join(getattr(habit, "title", [])) == "Move daily";
}

test "login carries its server override and registration flag" {
    parser = build_parser();
    plain = parser.parse_args(["login", "hunter"]);
    assert text_of(plain, "username") == "hunter";
    assert text_of(plain, "server") == "";
    assert not flag_of(plain, "register");
    hosted = parser.parse_args(
        ["login", "hunter", "--server", "https://arbor.example", "--register"]
    );
    assert text_of(hosted, "server") == "https://arbor.example";
    assert flag_of(hosted, "register");
}

test "the accessor helpers never raise on a missing attribute" {
    parsed = build_parser().parse_args(["today"]);
    assert text_of(parsed, "not_a_field") == "";
    assert number_of(parsed, "not_a_field", 7) == 7;
    assert not flag_of(parsed, "not_a_field");
}
