"""Shared plumbing for the Arbor CLI: session, bridge wiring, and output.

The CLI is a real client of the `planner` service, not a second
implementation of it. Commands `import from core.planner { ... }`, which the
compiler turns into typed async stubs that call the running server over the
app bridge, so the terminal, the browser and the phone all go through the
same endpoints and the same per-user graph.
"""

import json;
import os;
import sys;
import urllib.error;
import urllib.request;
import from pathlib { Path }
import from jaclang.server { sv_client }
import from jaclang.server.bridge {
    BridgeError,
    BridgeRejected,
    BridgeTimeout,
    BridgeUnavailable
}

glob PROVIDER_APP: str = "planner",
     PROVIDER_ROUTE: str = "/api/planner",
     DEFAULT_SERVER: str = "http://localhost:8000";

glob EXIT_OK: int = 0,
     EXIT_FAILURE: int = 1,
     EXIT_USAGE: int = 2,
     EXIT_UNAVAILABLE: int = 3,
     EXIT_TIMEOUT: int = 4,
     EXIT_AUTH: int = 5;

glob START_HINT: str = "hint: start the planner with `jac run` in the repo root";

glob LOGIN_HINT: str = "hint: sign in first with `arbor login <username>`";

obj Session {
    """What the CLI remembers between invocations."""

    has server: str = DEFAULT_SERVER,
        token: str = "",
        username: str = "";
}


"""Where the session file lives; override with ARBOR_HOME."""
def session_path -> Path {
    home = os.environ.get("ARBOR_HOME", "").strip();
    base = Path(home) if home else Path.home() / ".arbor";
    return base / "session.json";
}


"""Print to stderr so stdout stays clean for piping."""
def warn(text: str) {
    print(text, file=sys.stderr);
}


"""Read the stored session, falling back to environment overrides."""
def load_session -> Session {
    stored: dict[str, any] = {};
    path = session_path();
    if path.exists() {
        try {
            stored = json.loads(path.read_text());
        } except Exception {
            stored = {};
        }
    }
    return Session(
        server=os.environ.get("ARBOR_SERVER", "").strip()
            or str(stored.get("server", "") or DEFAULT_SERVER),
        token=os.environ.get("ARBOR_TOKEN", "").strip()
            or str(stored.get("token", "") or ""),
        username=str(stored.get("username", "") or "")
    );
}


"""Persist the session with owner-only permissions -- it holds a token."""
def save_session(session: Session) {
    path = session_path();
    path.parent.mkdir(parents=True, exist_ok=True);
    path.write_text(
        json.dumps(
            {
                "server": session.server,
                "token": session.token,
                "username": session.username
            },
            indent=2
        )
    );
    try {
        os.chmod(path, 0o600);
    } except OSError {}
}


"""Forget the stored session."""
def clear_session {
    path = session_path();
    if path.exists() {
        path.unlink();
    }
}


"""Point the bridge at a running server and carry the user's token on it.

`JAC_APP_PLANNER_URL` / `_ROUTE` are what the bridge resolver looks for, and
`set_bearer_token` puts the signed-in identity on every outgoing call, so a
`def:protect` endpoint runs against this user's own root.
"""
def connect(session: Session) {
    base = session.server.rstrip("/");
    os.environ[sv_client.peer_url_env_key(PROVIDER_APP)] = base;
    os.environ[sv_client.peer_route_env_key(PROVIDER_APP)] = PROVIDER_ROUTE;
    sv_client.register(PROVIDER_APP, base, PROVIDER_ROUTE);
    sv_client.set_bearer_token(session.token);
}


"""Turn a bridge failure into a clear message and a meaningful exit code."""
def explain(error: BridgeError) -> int {
    where = PROVIDER_APP + "." + error.name if error.name else PROVIDER_APP;
    detail = f" ({error.detail})" if error.detail else "";
    if isinstance(error, BridgeUnavailable) {
        warn(f"arbor: cannot reach the planner service{detail}");
        warn(START_HINT);
        return EXIT_UNAVAILABLE;
    }
    if isinstance(error, BridgeTimeout) {
        warn(f"arbor: {where} timed out{detail}");
        return EXIT_TIMEOUT;
    }
    if isinstance(error, BridgeRejected) {
        warn(f"arbor: the planner refused the call{detail}");
        warn(LOGIN_HINT);
        return EXIT_AUTH;
    }
    warn(f"arbor: {where} failed{detail}");
    return EXIT_FAILURE;
}


"""Map any thrown error onto an exit code, bridge-aware."""
def exit_code_for(error: Exception) -> int {
    if isinstance(error, BridgeError) {
        return explain(error);
    }
    text = str(error);
    if "UNAUTHORIZED" in text.upper() {
        warn("arbor: your session is not valid any more");
        warn(LOGIN_HINT);
        return EXIT_AUTH;
    }
    warn("arbor: " + (text or "something went wrong"));
    return EXIT_FAILURE;
}


"""POST JSON to the server's own REST surface (used only for auth)."""
def post_json(server: str, path: str, body: dict[str, any]) -> dict[str, any] {
    request = urllib.request.Request(
        server.rstrip("/") + path,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    );
    try {
        response = urllib.request.urlopen(request, timeout=15);
    } except urllib.error.HTTPError as e {
        try {
            return {"ok": False, "error": json.loads(e.read().decode("utf-8"))};
        } except Exception {
            return {"ok": False, "error": {"message": f"HTTP {e.code}"}};
        }
    } except Exception as e {
        return {"ok": False, "error": {"message": str(e)}};
    }
    try {
        return json.loads(response.read().decode("utf-8"));
    } finally {
        response.close();
    }
}


# --- Terminal rendering ------------------------------------------------------

import from core.contracts { NO_DUE_DATE, TaskView }

glob COLOR_STATE: list[bool] = [];

glob DIM: str = "2",
     BOLD: str = "1",
     RED: str = "31",
     GREEN: str = "32",
     YELLOW: str = "33",
     BLUE: str = "34",
     MAGENTA: str = "35",
     CYAN: str = "36";


"""Whether to emit ANSI codes: only on a terminal, and never under NO_COLOR."""
def use_color -> bool {
    if not COLOR_STATE {
        COLOR_STATE.append(
            sys.stdout.isatty() and not os.environ.get("NO_COLOR", "").strip()
        );
    }
    return COLOR_STATE[0];
}


"""Wrap `text` in an ANSI code when colour is in play."""
def paint(text: str, code: str) -> str {
    if not use_color() or not text {
        return text;
    }
    return "\x1b[" + code + "m" + text + "\x1b[0m";
}


"""Left-pad to `width`, truncating with an ellipsis when too long."""
def fit(text: str, width: int) -> str {
    if len(text) <= width {
        return text + " " * (width - len(text));
    }
    return text[:width - 1] + "…";
}


"""The first six characters of a node id -- enough to name a task by hand."""
def short_id(value: str) -> str {
    return value[:6];
}


"""Minutes as a compact "2h 30m"."""
def duration(total: int) -> str {
    if total <= 0 {
        return "0m";
    }
    hours = total // 60;
    mins = total % 60;
    if hours == 0 {
        return str(mins) + "m";
    }
    if mins == 0 {
        return str(hours) + "h";
    }
    return str(hours) + "h" + str(mins) + "m";
}


"""Minutes from midnight as 24-hour HH:MM."""
def clock(minutes: int) -> str {
    hours = minutes // 60;
    mins = minutes % 60;
    return ("0" + str(hours) if hours < 10 else str(hours)) + ":" + ("0" + str(mins) if mins < 10 else str(mins));
}


"""A deadline phrased relative to today, already coloured for urgency."""
def due_text(task: TaskView) -> str {
    if task.days_until == NO_DUE_DATE {
        return paint("someday", DIM);
    }
    if task.days_until < 0 {
        return paint("overdue " + str(-task.days_until) + "d", RED);
    }
    if task.days_until == 0 {
        return paint("today", YELLOW);
    }
    if task.days_until == 1 {
        return "tomorrow";
    }
    return "in " + str(task.days_until) + "d";
}


"""Colour a priority word by how loudly it should shout."""
def priority_text(priority: str) -> str {
    if priority == "critical" {
        return paint(priority, RED);
    }
    if priority == "high" {
        return paint(priority, YELLOW);
    }
    if priority == "low" {
        return paint(priority, DIM);
    }
    return priority;
}


"""One aligned task row: id, state, course, title, deadline, size, priority."""
def task_line(task: TaskView) -> str {
    mark = paint("✔", GREEN) if task.done else "·";
    title = paint(fit(task.title, 38), DIM) if task.done else fit(task.title, 38);
    course = paint(fit(task.course_code or "—", 9), CYAN);
    return (
        "  "
            + paint(short_id(task.id), DIM)
            + "  "
            + mark
            + "  "
            + course
            + "  "
            + title
            + "  "
            + fit(due_text(task), 22)
            + fit(duration(task.estimate_minutes), 7)
            + priority_text(task.priority)
    );
}


"""A section heading with a count."""
def heading(label: str, count: int) {
    heading_note(label, "(" + str(count) + ")");
}


"""A section heading with an arbitrary note after it."""
def heading_note(label: str, note: str) {
    print();
    print(paint(label.upper(), BOLD) + paint("  " + note, DIM));
}


"""Print a list of tasks, or a dim placeholder when there are none."""
def print_tasks(tasks: list[TaskView], empty: str) {
    if not tasks {
        print(paint("  " + empty, DIM));
        return;
    }
    for task in tasks {
        print(task_line(task));
    }
}


"""Find one task by exact id, id prefix, or a case-insensitive title match."""
def resolve_task(needle: str, tasks: list[TaskView]) -> TaskView | None {
    wanted = needle.strip().lower();
    if not wanted {
        return None;
    }
    for task in tasks {
        if task.id.lower() == wanted {
            return task;
        }
    }
    by_prefix = [t for t in tasks if t.id.lower().startswith(wanted)];
    if len(by_prefix) == 1 {
        return by_prefix[0];
    }
    by_title = [t for t in tasks if wanted in t.title.lower()];
    if len(by_title) == 1 {
        return by_title[0];
    }
    candidates = by_prefix + [t for t in by_title if t not in by_prefix];
    if len(candidates) > 1 {
        warn("arbor: \"" + needle + "\" matches more than one task:");
        for task in candidates[:8] {
            warn("    " + short_id(task.id) + "  " + task.title);
        }
    }
    return None;
}
