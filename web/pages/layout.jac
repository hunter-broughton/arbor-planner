"""The application shell: terminal bar, sidebar, and global keyboard control.

The chrome borrows from hunterbroughton.com -- a monospace status strip
pinned to the top, a bracketed wordmark, Michigan maize against neon blue.
`/login` renders bare so the sign-in screen gets the whole viewport.
"""

import from "@jac/runtime" { Link, Outlet, jacLogout, useLocation, useNavigate }

import from core.planner { StatusView, service_status }

glob NAV_ITEMS: list[tuple[str, str, str]] = [
    ("/", "Today", "1"),
    ("/week", "Week", "2"),
    ("/courses", "Courses", "3"),
    ("/habits", "Habits", "4"),
    ("/settings", "Settings", "5")
];

glob SHORTCUTS: list[tuple[str, str]] = [
    ("1 … 5", "Jump to Today, Week, Courses, Habits, Settings"),
    ("/", "Focus the quick-capture box"),
    ("p", "Build today's plan"),
    ("r", "Reload from the server"),
    ("?", "Show this list"),
    ("Esc", "Close")
];


def:pub layout -> JsxLayout {
    has status: StatusView = StatusView(),
        clock: str = "",
        showKeys: bool = False;

    location = useLocation();
    navigate = useNavigate();

    async can with entry {
        try {
            status = await service_status();
        } except Exception {
            status = StatusView(ok=False);
        }
    }

    # A global key map, the way a terminal-shaped app ought to work. Typing
    # into a field is never intercepted.
    can with entry {
        handler = lambda (e: any) {
            tag = str(e.target.tagName or "").upper();
            if tag == "INPUT" or tag == "TEXTAREA" or tag == "SELECT" {
                if e.key == "Escape" { e.target.blur(); }
                return;
            }
            if e.metaKey or e.ctrlKey or e.altKey { return; }
            if e.key == "?" { showKeys = not showKeys; return; }
            if e.key == "Escape" { showKeys = False; return; }
            for (path, label, digit) in NAV_ITEMS {
                if e.key == digit {
                    showKeys = False;
                    navigate(path);
                    return;
                }
            }
            if e.key == "r" {
                window.location.reload();
                return;
            }
            if e.key == "p" {
                doc: any = document;
                maker: any = CustomEvent;
                doc.dispatchEvent(new(maker, "hunterplan:plan"));
                return;
            }
            if e.key == "/" {
                box: any = document.getElementById("quickcapture");
                if box {
                    e.preventDefault();
                    box.focus();
                }
            }
        };
        document.addEventListener("keydown", handler);
        tick = lambda {
            now = new(Date);
            clock = now.toLocaleTimeString("en-US", {"hour12": False});
        };
        tick();
        timer = setInterval(tick, 1000);
        return lambda {
            document.removeEventListener("keydown", handler);
            clearInterval(timer);
        };
    }

    def signOut {
        jacLogout();
        navigate("/login", {"replace": True});
    }

    def linkClass(path: str) -> str {
        return "nav-link is-active" if location.pathname == path else "nav-link";
    }

    def currentLabel -> str {
        for (path, label, digit) in NAV_ITEMS {
            if location.pathname == path {
                return label.lower();
            }
        }
        return "planner";
    }

    if location.pathname == "/login" {
        return <Outlet/>;
    }

    return
        <div>
            <div className="scanline"/>
            <div className="termbar">
                <span className="termbar-path">~/hunterplan</span>
                <span className="termbar-prompt">$</span>
                <span className="termbar-cmd">{"hunt " + currentLabel()}</span>
                <span className="caret"/>
                <span className="termbar-right">
                    <span className="termbar-stat">
                        {str(status.open_tasks) + " open · " + str(status.courses) + " courses"}
                    </span>
                    <span className="termbar-stat">
                        {("ai:" + status.ai_model) if status.ai_enabled else "ai:off"}
                    </span>
                    <span className="termbar-key">
                        {"press ? for keys"}
                    </span>
                    <span className="termbar-path">{clock}</span>
                </span>
            </div>

            <div className="shell">
                <aside className="sidebar">
                    <div className="wordmark">
                        <span className="wordmark-b">&lt;</span>
                        <span className="wordmark-1">Hunter</span>
                        <span className="wordmark-slash">/</span>
                        <span className="wordmark-2">Plan</span>
                        <span className="wordmark-b">&gt;</span>
                    </div>
                    <nav className="nav">
                        {[
                            <Link key={path} to={path} className={linkClass(path)}>
                                <span>{label}</span>
                                <span className="row" style={{"gap": "6px"}}>
                                    {(
                                        <span className="nav-count">
                                            {str(status.open_tasks)}
                                        </span>
                                    ) if path == "/" and status.open_tasks > 0 else None}
                                    {(
                                        <span className="nav-count">
                                            {str(status.courses)}
                                        </span>
                                    ) if path == "/courses" and status.courses > 0 else None}
                                    <span className="nav-key">{digit}</span>
                                </span>
                            </Link> for (path, label, digit) in NAV_ITEMS
                        ]}
                    </nav>
                    <div className="sidebar-foot">
                        <span className={"pill pill-accent" if status.ai_enabled else "pill"}>
                            {("ai assist on" if status.ai_enabled else "ai assist off")}
                        </span>
                        <button className="btn btn-ghost btn-sm" onClick={signOut}>
                            Sign out
                        </button>
                    </div>
                </aside>
                <main className="main">
                    <Outlet/>
                </main>
            </div>

            {(
                <div className="overlay" onClick={lambda { showKeys = False; }}>
                    <div className="card overlay-card">
                        <h2 className="overlay-title">Keyboard</h2>
                        {[
                            <div key={keys} className="key-row">
                                <span className="kbd">{keys}</span>
                                <span className="muted">{what}</span>
                            </div> for (keys, what) in SHORTCUTS
                        ]}
                    </div>
                </div>
            ) if showKeys else None}
        </div>;
}
