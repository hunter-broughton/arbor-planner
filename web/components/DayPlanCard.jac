"""The time-blocked schedule for a day."""

import from core.contracts { PlanResult }
import from web.fmt { clock, duration }


def:pub DayPlanCard(
    plan: PlanResult,
    busy: bool,
    onPlan: Callable[[], None],
    onClear: Callable[[], None]
) -> JsxElement {
    return
        <section className="card">
            <div className="card-head">
                <h2 className="card-title">Day plan</h2>
                <div className="row">
                    {(
                        <span className="pill tabular">
                            {duration(plan.planned_minutes)}
                        </span>
                    ) if plan.planned_minutes > 0 else None}
                    <button
                        className="btn btn-sm"
                        onClick={onPlan}
                        disabled={busy}
                    >
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
                        No schedule yet. Build one and Arbor will lay your open
                        work into focus blocks, most urgent first.
                    </div>
                ) if len(plan.blocks) == 0 else (
                    <div className="timeline">
                        {[
                            <div
                                key={block.id}
                                className={"slot is-break" if block.kind == "break" else "slot"}
                            >
                                <div className="slot-time">
                                    {clock(block.start_min) + " – " + clock(block.end_min)}
                                </div>
                                <div className="slot-bar"/>
                                <div className="grow">
                                    <div className="slot-label">{block.label}</div>
                                    <div className="slot-why">{block.rationale}</div>
                                </div>
                            </div> for block in plan.blocks
                        ]}
                    </div>
                )}
            </div>
            {(
                <div className="card-body" style={{"borderTop": "1px solid var(--border)"}}>
                    <div className="faint" style={{"fontSize": "12.5px"}}>
                        {"Did not fit: " + ", ".join([t.title for t in plan.unplanned[:4]])}
                        {("..." if len(plan.unplanned) > 4 else "")}
                    </div>
                </div>
            ) if len(plan.unplanned) > 0 else None}
        </section>;
}
