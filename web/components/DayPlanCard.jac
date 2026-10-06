"""The time-blocked schedule for today, with a live "you are here" line.

The marker tracks the wall clock and slides between blocks, and anything
already behind it dims -- so a glance tells you whether you are on plan
without reading a single timestamp.
"""

import from core.contracts { PlanResult }
import from web.fmt { clock, duration }


def:pub DayPlanCard(
    plan: PlanResult,
    busy: bool,
    onPlan: Callable[[], None],
    onClear: Callable[[], None]
) -> JsxElement {
    has nowMinutes: int = 0;

    can with entry {
        read = lambda {
            stamp = new(Date);
            nowMinutes = int(stamp.getHours()) * 60 + int(stamp.getMinutes());
        };
        read();
        timer = setInterval(read, 30000);
        return lambda { clearInterval(timer); };
    }

    def isLive(start: int, end: int) -> bool {
        return start <= nowMinutes and nowMinutes < end;
    }

    return
        <section className="card rise rise-1">
            <div className="card-head">
                <h2 className="card-title">Day plan</h2>
                <div className="row">
                    {(
                        <span className="pill tabular">
                            {duration(plan.planned_minutes)}
                        </span>
                    ) if plan.planned_minutes > 0 else None}
                    <button className="btn btn-sm" onClick={onPlan} disabled={busy}>
                        {("Planning..." if busy else ("Replan" if len(plan.blocks) > 0 else "Build plan"))}
                    </button>
                    {(
                        <button className="btn btn-ghost btn-sm" onClick={onClear}>
                            Clear
                        </button>
                    ) if len(plan.blocks) > 0 else None}
                </div>
            </div>
            <div className="card-body flush">
                {(
                    <div className="empty">
                        No schedule yet. Build one and HunterPlan will lay your
                        open work into focus blocks, most urgent first.
                    </div>
                ) if len(plan.blocks) == 0 else (
                    <div className="timeline">
                        {[
                            <div key={block.id}>
                                {(
                                    <div className="nowline">
                                        <div className="nowline-inner">
                                            <span className="nowline-dot pulse"/>
                                            <span className="nowline-text">
                                                {"NOW " + clock(nowMinutes)}
                                            </span>
                                            <span className="nowline-rule"/>
                                        </div>
                                    </div>
                                ) if isLive(block.start_min, block.end_min) else None}
                                <div
                                    className={
                                        ("slot is-" + block.kind if block.kind != "focus" else "slot")
                                            + (" is-past" if block.end_min <= nowMinutes else "")
                                    }
                                >
                                    <div className="slot-time">
                                        {clock(block.start_min) + " – " + clock(block.end_min)}
                                    </div>
                                    <div className="slot-bar"/>
                                    <div className="grow">
                                        <div className="slot-label">{block.label}</div>
                                        <div className="slot-why">{block.rationale}</div>
                                    </div>
                                </div>
                            </div> for block in plan.blocks
                        ]}
                    </div>
                )}
            </div>
            {(
                <div className="card-body" style={{"borderTop": "1px solid var(--line)"}}>
                    <div className="faint mono" style={{"fontSize": "11.5px"}}>
                        {"did not fit: " + ", ".join([t.title for t in plan.unplanned[:4]])}
                        {("…" if len(plan.unplanned) > 4 else "")}
                    </div>
                </div>
            ) if len(plan.unplanned) > 0 else None}
        </section>;
}
