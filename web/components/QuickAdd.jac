"""Natural-language capture.

One text box. The server reads the line -- with a model when one is
configured, with a regex-and-cue parser when not -- and echoes back exactly
how it understood it, so a wrong guess is visible instead of silent.
"""

import from core.planner { QuickAddResult, quick_add }


def:pub QuickAdd(onAdded: Callable[[], None]) -> JsxElement {
    has text: str = "",
        busy: bool = False,
        reading: QuickAddResult | None = None,
        error: str = "";

    async def submit {
        result: QuickAddResult | None = None;
        if not text.strip() or busy {
            return;
        }
        busy = True;
        error = "";
        try {
            result = await quick_add(text.strip());
        } except Exception {
            busy = False;
            error = "Could not reach the planner service.";
            return;
        }
        busy = False;
        reading = result;
        text = "";
        onAdded();
    }

    return
        <section className="card">
            <div className="card-body">
                <div className="quickadd">
                    <input
                        className="input grow"
                        value={text}
                        placeholder="EECS 449 project proposal due friday 5pm ~3h urgent"
                        onChange={lambda (e: ChangeEvent) { text = e.target.value; }}
                        onKeyDown={lambda (e: KeyboardEvent) {
                            if e.key == "Enter" { submit(); }
                        }}
                    />
                    <button
                        className="btn btn-primary"
                        onClick={lambda { submit(); }}
                        disabled={busy}
                    >
                        {("Reading..." if busy else "Capture")}
                    </button>
                </div>
                {(<div className="banner banner-error" style={{"marginTop": "8px"}}>{error}</div>) if error else None}
                {(
                    <div className="quickadd-read">
                        <span className={"pill pill-accent" if reading.ai else "pill"}>
                            {("ai" if reading.ai else "parsed")}
                        </span>
                        <span>
                            {"\"" + reading.task.title + "\" — " + reading.interpreted}
                        </span>
                    </div>
                ) if reading is not None and reading.task.id else None}
            </div>
        </section>;
}
