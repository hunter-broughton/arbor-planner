"""Arbor web client -- the router shell.

File-based routing: everything under `web/pages/` is a route, `pages/layout.jac`
is the shell, and `pages/(auth)/` is wrapped in an authentication guard by the
build system. This file only has to load the stylesheet and render whatever
route tree the router hands it as `children`.
"""

import "./styles.css";

def:pub app(children: any) -> JsxElement {
    return <>{children}</>;
}
