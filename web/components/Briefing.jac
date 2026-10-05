"""The briefing card: headline, advice, and a load-versus-capacity meter."""

import from core.contracts { AgendaView }
import from web.fmt { duration }


def:pub Briefing(agenda: AgendaView) -> JsxElement {
    capacity = max(1, agenda.capacity_minutes);
    ratio = float(agenda.load_minutes) / float(capacity);
    over = agenda.load_minutes > capacity;
    width = str(int(min(1.0, ratio) * 100.0)) + "%";
    return
        <section className="card rise">
            <div className="briefing">
                <div className="briefing-body">
                    <h2 className="briefing-headline">
                        {agenda.headline or "Your day"}
                    </h2>
                    <p className="briefing-advice">{agenda.advice}</p>
                </div>
                <div className="briefing-meter">
                    <div className="meter-track">
                        <div
                            className={"meter-fill over" if over else "meter-fill"}
                            style={{"width": width}}
                        />
                    </div>
                    <div className="meter-label">
                        <span className="tabular">{duration(agenda.load_minutes)}</span>
                        <span className="tabular">
                            {"of " + duration(agenda.capacity_minutes)}
                        </span>
                    </div>
                    <div className="meter-label">
                        <span className={"pill pill-accent" if agenda.ai else "pill"}>
                            {("written by AI" if agenda.ai else "rule-based")}
                        </span>
                    </div>
                </div>
            </div>
        </section>;
}
