"""Sign in, sign out, and report who the terminal is acting as.

Authentication is the one thing the CLI does over plain REST rather than the
app bridge: `/user/login` issues the JWT that every bridged call then carries.
"""

import getpass;
import from core.planner { me, service_status }
import from cli.commands.common {
    BOLD,
    CYAN,
    DIM,
    EXIT_AUTH,
    EXIT_FAILURE,
    EXIT_OK,
    GREEN,
    Session,
    clear_session,
    connect,
    duration,
    exit_code_for,
    load_session,
    paint,
    post_json,
    save_session,
    warn
}


"""Read a password without echoing it, or take HUNTERPLAN_PASSWORD for scripts."""
def read_password(prompt: str) -> str {
    import os;
    preset = os.environ.get("HUNTERPLAN_PASSWORD", "");
    if preset {
        return preset;
    }
    return getpass.getpass(prompt);
}


"""Pull the error message out of a server envelope."""
def error_message(payload: dict[str, any]) -> str {
    detail = payload.get("error");
    if isinstance(detail, dict) {
        return str(detail.get("message", "") or detail.get("code", "") or "rejected");
    }
    return str(detail or "rejected");
}


"""`hunt login <username>` -- exchange credentials for a stored token."""
async def run_login(username: str, server: str, register: bool) -> int {
    session = load_session();
    target = (server or session.server).rstrip("/");
    password = read_password("password for " + username + ": ");
    if not password {
        warn("hunt login: no password given");
        return EXIT_AUTH;
    }
    if register {
        created = post_json(
            target,
            "/user/register",
            {
                "identities": [{"type": "username", "value": username}],
                "credential": {"type": "password", "password": password}
            }
        );
        if not created.get("ok") {
            warn("hunt login: could not create that account -- " + error_message(created));
            return EXIT_AUTH;
        }
    }
    answer = post_json(
        target,
        "/user/login",
        {
            "identity": {"type": "username", "value": username},
            "credential": {"type": "password", "password": password}
        }
    );
    if not answer.get("ok") {
        warn("hunt login: " + error_message(answer));
        return EXIT_AUTH;
    }
    data = answer.get("data") or {};
    token = str(data.get("token", "") or "");
    if not token {
        warn("hunt login: the server returned no token");
        return EXIT_AUTH;
    }
    save_session(Session(server=target, token=token, username=username));
    print(paint("✔", GREEN) + " signed in as " + paint(username, BOLD) + paint("  (" + target + ")", DIM));
    return EXIT_OK;
}


"""`hunt logout` -- forget the stored token."""
def run_logout -> int {
    clear_session();
    print("signed out");
    return EXIT_OK;
}


"""`hunt status` -- service health, capability and current identity."""
async def run_status -> int {
    session = load_session();
    connect(session);
    try {
        status = await service_status();
    } except Exception as e {
        return exit_code_for(e);
    }
    print(paint("HunterPlan planner", BOLD));
    print("  server      " + session.server);
    print("  service     " + paint("reachable", GREEN) + "  ·  " + status.server_date);
    print(
        "  ai assist   "
            + (paint(status.ai_model, CYAN) if status.ai_enabled else paint("not configured (deterministic fallbacks in use)", DIM))
    );
    if not session.token {
        print("  signed in   " + paint("no -- run `hunt login <username>`", DIM));
        return EXIT_OK;
    }
    try {
        profile = await me();
    } except Exception as e {
        return exit_code_for(e);
    }
    print("  signed in   " + paint(session.username or profile.display_name or "yes", BOLD));
    print(
        "  tracking    "
            + str(status.courses)
            + " courses · "
            + str(status.open_tasks)
            + " open tasks · "
            + str(status.goals)
            + " habits"
    );
    print("  capacity    " + duration(profile.daily_capacity_minutes) + " of focus per day");
    return EXIT_OK;
}
