"""Sign in or create an account.

Signup does not open a session on its own, so a successful registration is
immediately followed by a login before the first authenticated call.
"""

import from "@jac/runtime" { SignupResult, jacLogin, jacSignup, useNavigate }


def:pub page -> JsxPage {
    has mode: str = "signin",
        username: str = "",
        password: str = "",
        error: str = "",
        busy: bool = False;

    navigate = useNavigate();

    async def submit(e: FormEvent) {
        signup: SignupResult | None = None;
        ok: bool = False;
        e.preventDefault();
        error = "";
        if not username.strip() or not password {
            error = "Enter a username and a password.";
            return;
        }
        if mode == "signup" and len(password) < 6 {
            error = "Use at least 6 characters for the password.";
            return;
        }
        busy = True;
        try {
            if mode == "signup" {
                signup = await jacSignup(username.strip(), password);
                if not signup.success {
                    busy = False;
                    error = str(signup.error) or "That username is taken.";
                    return;
                }
            }
            ok = await jacLogin(username.strip(), password);
        } except Exception {
            busy = False;
            error = "Could not reach the planner service.";
            return;
        }
        busy = False;
        if ok {
            navigate("/", {"replace": True});
        } else {
            error = "Those credentials did not work.";
        }
    }

    def flip {
        mode = "signin" if mode == "signup" else "signup";
        error = "";
    }

    return
        <div className="auth-wrap">
            <div className="card auth-card">
                <div className="wordmark" style={{"padding": "0"}}>
                    <div className="wordmark-glyph">A</div>
                    <div className="wordmark-text">Arbor</div>
                </div>
                <h1 className="auth-title">
                    {("Create your planner" if mode == "signup" else "Welcome back")}
                </h1>
                <p className="auth-sub">
                    Coursework, focus blocks and habits -- on the web, on your
                    phone, and in your terminal.
                </p>
                {(<div className="banner banner-error">{error}</div>) if error else None}
                <form onSubmit={submit} className="stack" style={{"marginTop": "14px"}}>
                    <div className="field">
                        <label className="field-label">Username</label>
                        <input
                            className="input"
                            value={username}
                            autoComplete="username"
                            placeholder="your uniqname"
                            onChange={lambda (e: ChangeEvent) { username = e.target.value; }}
                        />
                    </div>
                    <div className="field">
                        <label className="field-label">Password</label>
                        <input
                            className="input"
                            type="password"
                            value={password}
                            autoComplete={("new-password" if mode == "signup" else "current-password")}
                            placeholder="at least 6 characters"
                            onChange={lambda (e: ChangeEvent) { password = e.target.value; }}
                        />
                    </div>
                    <button type="submit" className="btn btn-primary" disabled={busy}>
                        {(
                            "Working..."
                                if busy
                                else ("Create account" if mode == "signup" else "Sign in")
                        )}
                    </button>
                </form>
                <div className="auth-switch">
                    {(
                        "Already have an account? "
                            if mode == "signup"
                            else "New here? "
                    )}
                    <button type="button" className="auth-link" onClick={flip}>
                        {("Sign in" if mode == "signup" else "Create one")}
                    </button>
                </div>
            </div>
        </div>;
}
