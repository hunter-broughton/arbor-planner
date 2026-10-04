"""`arbor` -- the Arbor planner from the terminal.

A thin, fast client of the `planner` service. Every subcommand below is a
bridged call to the same endpoints the web app and the phone app use, which
is why a task captured here shows up in the browser without a refresh story
of its own.

    jac run cli -- today
    jac run cli -- add "EECS 449 project proposal due friday 5pm ~3h urgent"
    ./arbor done pagination

`./arbor` is a one-line wrapper over `jac run cli --`.
"""

import argparse;
import asyncio;
import sys;
import from cli.commands.auth { run_login, run_logout, run_status }
import from cli.commands.common {
    EXIT_OK,
    EXIT_USAGE,
    connect,
    load_session,
    warn
}
import from cli.commands.planning {
    run_add_course,
    run_add_habit,
    run_check_habit,
    run_clear_plan,
    run_courses,
    run_data,
    run_habits,
    run_plan,
    run_remove_course,
    run_week
}
import from cli.commands.tasks {
    run_add,
    run_complete,
    run_list,
    run_remove,
    run_split,
    run_today
}

glob PROG: str = "arbor";

glob EPILOG: str = """examples:
  arbor login hunter                      sign in (use --register the first time)
  arbor today                             the whole day in one screen
  arbor add "EECS 449 proposal due fri 5pm ~3h urgent"
  arbor ls --course "EECS 485"            open work for one class
  arbor done pagination                   complete by id prefix or title match
  arbor split "project proposal"          break a big task into work sessions
  arbor plan --minutes 300                build a time-blocked day
  arbor week --offset 1                   look at next week
  arbor check gym                         tick a habit for today
""";


"""Build the whole command surface in one place."""
def build_parser -> argparse.ArgumentParser {
    parser = argparse.ArgumentParser(
        prog=PROG,
        description="Arbor -- a personal academic planner, from the terminal.",
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter
    );
    commands = parser.add_subparsers(dest="command", metavar="<command>", required=True);

    login = commands.add_parser("login", help="sign in and store a session token");
    login.add_argument("username");
    login.add_argument("--server", `default="", help="planner URL (default http://localhost:8000)");
    login.add_argument(
        "--register", action="store_true", help="create the account first"
    );

    commands.add_parser("logout", help="forget the stored session");
    commands.add_parser("status", help="service health, AI capability and identity");
    commands.add_parser("today", help="agenda, day plan and habits for today");

    adder = commands.add_parser("add", help="capture a task from one line of text");
    adder.add_argument("text", nargs="+", help="e.g. \"pset 4 eecs445 due friday ~2h\"");

    lister = commands.add_parser("ls", help="list open tasks, most urgent first");
    lister.add_argument("--all", dest="include_done", action="store_true", help="include completed work");
    lister.add_argument("--course", `default="", help="limit to one course code");

    done = commands.add_parser("done", help="mark a task complete");
    done.add_argument("task", help="id prefix or part of the title");

    undone = commands.add_parser("undone", help="reopen a completed task");
    undone.add_argument("task");

    remover = commands.add_parser("rm", help="delete a task and its subtasks");
    remover.add_argument("task");

    splitter = commands.add_parser("split", help="break a task into work sessions");
    splitter.add_argument("task");

    planner = commands.add_parser("plan", help="build or show today's schedule");
    planner.add_argument("--minutes", `type=int, `default=0, help="focus budget for today");
    planner.add_argument("--show", action="store_true", help="show the stored plan without rebuilding");
    planner.add_argument("--clear", action="store_true", help="throw the stored plan away");

    week = commands.add_parser("week", help="seven days of deadlines");
    week.add_argument("--offset", `type=int, `default=0, help="weeks from this one");

    commands.add_parser("courses", help="courses with workload rolled up");
    course = commands.add_parser("course", help="add or remove a course");
    course_actions = course.add_subparsers(dest="action", metavar="<action>", required=True);
    course_add = course_actions.add_parser("add", help="add a course");
    course_add.add_argument("code", help="e.g. \"EECS 449\"");
    course_add.add_argument("--title", `default="");
    course_add.add_argument("--credits", `type=int, `default=0);
    course_rm = course_actions.add_parser("rm", help="remove a course");
    course_rm.add_argument("code");

    commands.add_parser("habits", help="habits and their streaks");
    habit = commands.add_parser("habit", help="add a habit");
    habit_actions = habit.add_subparsers(dest="action", metavar="<action>", required=True);
    habit_add = habit_actions.add_parser("add", help="track a new habit");
    habit_add.add_argument("title", nargs="+");
    habit_add.add_argument("--weekly", action="store_true", help="weekly instead of daily");
    habit_add.add_argument("--target", `type=int, `default=1, help="times per period");

    checker = commands.add_parser("check", help="tick a habit for today");
    checker.add_argument("habit");
    unchecker = commands.add_parser("uncheck", help="undo today's check-in");
    unchecker.add_argument("habit");

    commands.add_parser("seed", help="fill an empty account with a sample term");
    commands.add_parser("reset", help="delete every course, task, plan and habit");
    return parser;
}


"""Read a namespace attribute as a string without tripping the type checker."""
def text_of(namespace: any, name: str) -> str {
    return str(getattr(namespace, name, "") or "");
}


"""Read a namespace attribute as an int."""
def number_of(namespace: any, name: str, fallback: int = 0) -> int {
    return int(getattr(namespace, name, fallback) or fallback);
}


"""Read a namespace flag."""
def flag_of(namespace: any, name: str) -> bool {
    return bool(getattr(namespace, name, False));
}


"""Route one parsed invocation to its command."""
async def dispatch(args: any) -> int {
    command = text_of(args, "command");
    if command == "login" {
        return await run_login(
            text_of(args, "username"), text_of(args, "server"), flag_of(args, "register")
        );
    }
    if command == "logout" {
        return run_logout();
    }

    # Everything past this point talks to the planner, so wire the bridge to
    # the stored server and identity exactly once.
    connect(load_session());

    if command == "status" {
        return await run_status();
    }
    if command == "today" {
        return await run_today();
    }
    if command == "add" {
        return await run_add(" ".join(getattr(args, "text", []) or []));
    }
    if command == "ls" {
        return await run_list(flag_of(args, "include_done"), text_of(args, "course"));
    }
    if command == "done" {
        return await run_complete(text_of(args, "task"), True);
    }
    if command == "undone" {
        return await run_complete(text_of(args, "task"), False);
    }
    if command == "rm" {
        return await run_remove(text_of(args, "task"));
    }
    if command == "split" {
        return await run_split(text_of(args, "task"));
    }
    if command == "plan" {
        if flag_of(args, "clear") {
            return await run_clear_plan();
        }
        return await run_plan(number_of(args, "minutes"), flag_of(args, "show"));
    }
    if command == "week" {
        return await run_week(number_of(args, "offset"));
    }
    if command == "courses" {
        return await run_courses();
    }
    if command == "course" {
        if text_of(args, "action") == "add" {
            return await run_add_course(
                text_of(args, "code"), text_of(args, "title"), number_of(args, "credits")
            );
        }
        return await run_remove_course(text_of(args, "code"));
    }
    if command == "habits" {
        return await run_habits();
    }
    if command == "habit" {
        return await run_add_habit(
            " ".join(getattr(args, "title", []) or []),
            flag_of(args, "weekly"),
            number_of(args, "target", 1)
        );
    }
    if command == "check" {
        return await run_check_habit(text_of(args, "habit"), False);
    }
    if command == "uncheck" {
        return await run_check_habit(text_of(args, "habit"), True);
    }
    if command == "seed" {
        return await run_data(False);
    }
    if command == "reset" {
        return await run_data(True);
    }
    warn("arbor: unknown command " + command);
    return EXIT_USAGE;
}


async def main(argv: list[str]) -> int {
    return await dispatch(build_parser().parse_args(argv));
}


with entry:__main__ {
    sys.`exit(asyncio.run(main(sys.argv[1:])));
}
