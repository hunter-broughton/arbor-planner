"""The application shell: sidebar navigation and the signed-in chrome.

Wraps every route. `/login` is rendered bare so the sign-in screen gets the
whole viewport; everything else gets the sidebar.
"""

import from "@jac/runtime" { Link, Outlet, jacLogout, useLocation, useNavigate }

import from core.planner { StatusView, service_status }

glob NAV_ITEMS: list[tuple[str, str]] = [
    ("/", "Today"),
    ("/week", "Week"),
    ("/courses", "Courses"),
    ("/habits", "Habits"),
    ("/settings", "Settings")
];


def:pub layout -> JsxLayout {
    has status: StatusView = StatusView(),
        loaded: bool = False;

    location = useLocation();
    navigate = useNavigate();

    async can with entry {
        try {
            status = await service_status();
        } except Exception {
            status = StatusView(ok=False);
        }
        loaded = True;
    }

    def signOut {
        jacLogout();
        navigate("/login", {"replace": True});
    }

    def linkClass(path: str) -> str {
        return "nav-link is-active" if location.pathname == path else "nav-link";
    }

    if location.pathname == "/login" {
        return <Outlet/>;
    }

    return
        <div className="shell">
            <aside className="sidebar">
                <div className="wordmark">
                    <div className="wordmark-glyph">A</div>
                    <div className="wordmark-text">Arbor</div>
                    <div className="wordmark-sub">v1.0</div>
                </div>
                <nav className="nav">
                    {[
                        <Link key={path} to={path} className={linkClass(path)}>
                            <span>{label}</span>
                            {(
                                <span className="nav-count tabular">
                                    {str(status.open_tasks)}
                                </span>
                            ) if path == "/" and status.open_tasks > 0 else None}
                            {(
                                <span className="nav-count tabular">
                                    {str(status.courses)}
                                </span>
                            ) if path == "/courses" and status.courses > 0 else None}
                        </Link> for (path, label) in NAV_ITEMS
                    ]}
                </nav>
                <div className="sidebar-foot">
                    <span className={"pill pill-accent" if status.ai_enabled else "pill"}>
                        {("AI assist on" if status.ai_enabled else "AI assist off")}
                    </span>
                    <button className="btn btn-ghost btn-sm" onClick={signOut}>
                        Sign out
                    </button>
                </div>
            </aside>
            <main className="main">
                <Outlet/>
            </main>
        </div>;
}
