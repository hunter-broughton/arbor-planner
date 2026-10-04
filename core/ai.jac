"""AI-assisted planning, with a deterministic twin behind every call.

Three features here are delegated to a model with `by llm()`: reading a
free-text capture into a structured task, splitting a large assignment into a
work plan, and writing the morning briefing. Each one is paired with a plain
Jac implementation of the same signature.

The pairing is the point. `jac run` has to work for someone who just cloned
the repo and has no API key, so every entry point below asks `ai_available()`
first, and falls back the moment a model is missing, misconfigured, slow to
the point of erroring, or returns something that will not fit the type. The
planner never fails because the AI did.
"""

import os;
import re;
import from core.ranking { clean_kind, clean_priority }
import from core.timeutil {
    days_between,
    is_date,
    month_day,
    month_index,
    next_weekday,
    normalize_date,
    parse_clock,
    shift_days
}

glob DEFAULT_MODEL: str = "anthropic/claude-sonnet-5";

glob PROVIDER_KEYS: list[str] = [
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "GEMINI_API_KEY",
    "GOOGLE_API_KEY",
    "GROQ_API_KEY"
];

glob KEYLESS_PREFIXES: list[str] = ["local:", "ollama/"];

enum TaskKind {
    ASSIGNMENT,
    EXAM,
    READING,
    PROJECT,
    ADMIN,
    PERSONAL,
    FITNESS,
    SOCIAL,
    TASK
}

enum TaskPriority { LOW, MEDIUM, HIGH, CRITICAL }

sem TaskKind = "What sort of work a planner item is.";
sem TaskKind.ASSIGNMENT = "Homework, a problem set, a lab writeup, anything graded and turned in.";
sem TaskKind.EXAM = "A midterm, final, quiz, or the studying that leads directly into one.";
sem TaskKind.READING = "Assigned reading, a paper, lecture notes to get through.";
sem TaskKind.PROJECT = "Multi-session build or research work, usually with milestones.";
sem TaskKind.ADMIN = "Logistics: forms, registration, email, advising appointments.";
sem TaskKind.PERSONAL = "Errands and life admin outside of coursework.";
sem TaskKind.FITNESS = "Exercise, training, sport practice.";
sem TaskKind.SOCIAL = "Meeting people, club events, office hours as a social commitment.";
sem TaskKind.TASK = "Anything that does not fit the other kinds.";

sem TaskPriority = "How much this should outrank the rest of the queue.";
sem TaskPriority.LOW = "Nice to do; nothing breaks if it slips a week.";
sem TaskPriority.MEDIUM = "Normal coursework cadence.";
sem TaskPriority.HIGH = "Graded, soon, or blocking something else.";
sem TaskPriority.CRITICAL = "Due imminently and expensive to miss.";

obj ParsedTask {
    """The structured reading of a free-text capture."""

    has title: str = "",
        kind: TaskKind = TaskKind.TASK,
        priority: TaskPriority = TaskPriority.MEDIUM,
        due_date: str = "",
        due_time: str = "",
        estimate_minutes: int = 30,
        course_code: str = "";
}

sem ParsedTask.title = "The task itself, as a short imperative phrase. Strip out the deadline, the duration, the course code and any urgency words -- those belong in the other fields.";
sem ParsedTask.due_date = "The deadline as YYYY-MM-DD, resolved against the given current date. Empty string if the text names no deadline. Never invent one.";
sem ParsedTask.due_time = "Time of day as 24-hour HH:MM if the text names one, otherwise an empty string.";
sem ParsedTask.estimate_minutes = "Realistic focused working minutes for a university student, between 10 and 480. Use the text's own estimate when it gives one.";
sem ParsedTask.course_code = "The course code this belongs to, matched to one of the known course codes provided. Empty string when none of them fit.";

obj Subtask {
    """One step of a larger piece of work."""

    has title: str = "",
        estimate_minutes: int = 30;
}

sem Subtask.title = "A concrete step a student can sit down and finish in one session.";
sem Subtask.estimate_minutes = "Focused minutes for this step, between 15 and 180.";

obj DayBriefing {
    """The short coaching note above the agenda."""

    has headline: str = "",
        advice: str = "";
}

sem DayBriefing.headline = "Six words or fewer naming the shape of the day. No punctuation at the end.";
sem DayBriefing.advice = "One or two sentences of specific, practical advice about the order to work in. Name actual tasks from the context. No greetings, no pep talk.";

def:priv ai_parse_task(
    capture: str, current_date: str, current_weekday: str, known_courses: list[str]
) -> ParsedTask by llm(temperature=0.0);

sem ai_parse_task = "Read one line a student typed into a planner's quick-capture box and turn it into a structured task.";
sem ai_parse_task.capture = "The raw line the student typed.";
sem ai_parse_task.current_date = "Today's date as YYYY-MM-DD. Resolve every relative deadline against this.";
sem ai_parse_task.current_weekday = "The weekday name for the current date, so that 'friday' resolves correctly.";
sem ai_parse_task.known_courses = "Course codes the student is enrolled in. Only ever return one of these, or an empty string.";

def:priv ai_breakdown(
    title: str, notes: str, course: str, total_minutes: int, days_left: int
) -> list[Subtask] by llm(temperature=0.2);

sem ai_breakdown = "Split one large piece of coursework into three to six sequential work sessions that add up to roughly the given total.";
sem ai_breakdown.title = "The assignment being broken down.";
sem ai_breakdown.notes = "Any extra detail the student wrote down; may be empty.";
sem ai_breakdown.course = "The course code this belongs to; may be empty.";
sem ai_breakdown.total_minutes = "Roughly how many focused minutes the whole thing should take.";
sem ai_breakdown.days_left = "Days until the deadline, so the steps can be paced.";

def:priv ai_briefing(context: str) -> DayBriefing by llm(temperature=0.4);

sem ai_briefing = "Write the short briefing line at the top of a student's daily planner, given a plain-text digest of their day.";
sem ai_briefing.context = "A digest listing today's date, capacity, overdue work, work due today, and upcoming deadlines.";


"""The model id `by llm()` will use, honoring a BYLLM_DEFAULT_MODEL override."""
def:priv ai_model_name -> str {
    return os.environ.get("BYLLM_DEFAULT_MODEL", "").strip() or DEFAULT_MODEL;
}


"""Whether a model is actually reachable right now.

Set `ARBOR_DISABLE_AI=1` to force the deterministic path -- useful for tests
and for demonstrating that the planner is fully functional without a model.
"""
def:priv ai_available -> bool {
    if os.environ.get("ARBOR_DISABLE_AI", "").strip() {
        return False;
    }
    model = ai_model_name();
    for prefix in KEYLESS_PREFIXES {
        if model.startswith(prefix) {
            return True;
        }
    }
    for key in PROVIDER_KEYS {
        if os.environ.get(key, "").strip() {
            return True;
        }
    }
    return False;
}


"""`TaskKind.EXAM` -> "exam"."""
def:priv kind_name(value: TaskKind) -> str {
    return clean_kind(str(value).split(".")[-1].lower());
}


"""`TaskPriority.HIGH` -> "high"."""
def:priv priority_name(value: TaskPriority) -> str {
    return clean_priority(str(value).split(".")[-1].lower());
}


"""Map a lowercase kind string back onto the enum."""
def:priv kind_enum(value: str) -> TaskKind {
    table: dict[str, TaskKind] = {
        "assignment": TaskKind.ASSIGNMENT,
        "exam": TaskKind.EXAM,
        "reading": TaskKind.READING,
        "project": TaskKind.PROJECT,
        "admin": TaskKind.ADMIN,
        "personal": TaskKind.PERSONAL,
        "fitness": TaskKind.FITNESS,
        "social": TaskKind.SOCIAL
    };
    return table.get(clean_kind(value), TaskKind.TASK);
}


"""Map a lowercase priority string back onto the enum."""
def:priv priority_enum(value: str) -> TaskPriority {
    table: dict[str, TaskPriority] = {
        "low": TaskPriority.LOW,
        "medium": TaskPriority.MEDIUM,
        "high": TaskPriority.HIGH,
        "critical": TaskPriority.CRITICAL
    };
    return table.get(clean_priority(value), TaskPriority.MEDIUM);
}

# --- Deterministic fallbacks -------------------------------------------------
#
# Everything below runs with no model, no key and no network. It is what the
# planner uses by default, and what the `by llm()` functions above degrade to.

glob DEFAULT_MINUTES: dict[str, int] = {
    "assignment": 120,
    "exam": 180,
    "reading": 60,
    "project": 150,
    "admin": 20,
    "personal": 30,
    "fitness": 60,
    "social": 60,
    "task": 30
};

glob KIND_CUES: list[tuple[str, list[str]]] = [
    (
        "exam",
        ["midterm", "final exam", "final", "exam", "quiz", "study for", "studying for"]
    ),
    (
        "assignment",
        [
            "problem set",
            "pset",
            "homework",
            "hw",
            "assignment",
            "writeup",
            "write-up",
            "lab",
            "worksheet"
        ]
    ),
    ("reading", ["reading", "read ", "chapter", "textbook", "paper", "article"]),
    (
        "project",
        ["project", "proposal", "design doc", "implement", "build", "prototype", "demo"]
    ),
    (
        "admin",
        [
            "email",
            "register",
            "registration",
            "form",
            "advisor",
            "advising",
            "appointment",
            "renew",
            "pay "
        ]
    ),
    ("fitness", ["gym", "workout", "lift", "run ", "running", "swim", "practice"]),
    (
        "social",
        ["coffee", "dinner", "lunch", "club", "meeting", "meet ", "call ", "party"]
    ),
    ("personal", ["groceries", "laundry", "clean", "errand", "haircut", "doctor"])
];

glob CRITICAL_CUES: list[str] = ["urgent", "asap", "critical", "emergency", "!!!"];

glob HIGH_CUES: list[str] = ["important", "high priority", "top priority", "!!"];

glob LOW_CUES: list[str] = ["low priority", "whenever", "someday", "no rush", "eventually"];

glob FILLER_WORDS: list[str] = [
    "due",
    "by",
    "at",
    "on",
    "for",
    "the",
    "a",
    "an",
    "in",
    "before",
    "this",
    "next",
    "and",
    "-",
    "--",
    ":",
    ",",
    "."
];

glob BREAKDOWN_STAGES: list[str] = [
    "Read the spec and list every requirement",
    "Sketch the approach and set up the workspace",
    "Build the core of the solution",
    "Handle the hard cases and loose ends",
    "Test, debug, and check against the rubric",
    "Proofread, format, and submit"
];


"""Blank out `text[start:end]` without shifting the rest of the string."""
def:priv cut_span(text: str, start: int, end: int) -> str {
    return text[:start] + " " + text[end:];
}


"""Collapse runs of whitespace."""
def:priv squeeze(text: str) -> str {
    return re.sub(r"\s+", " ", text).strip();
}


"""Course code mentioned in `text`, matched against the student's own courses.

Returns the canonical code as the student wrote it when enrolled, so "eecs449"
and "EECS 449" both land on the same course.
"""
def:priv find_course(text: str, known_courses: list[str]) -> tuple[str, str] {
    lookup: dict[str, str] = {};
    for code in known_courses {
        lookup[re.sub(r"[^a-z0-9]", "", code.lower())] = code;
    }
    for hit in re.finditer(r"\b([A-Za-z]{2,6})\s*[- ]?\s*(\d{3}[A-Za-z]?)\b", text) {
        key = (hit.group(1) + hit.group(2)).lower();
        if key in lookup {
            return (lookup[key], cut_span(text, hit.start(), hit.end()));
        }
    }
    for code in known_courses {
        needle = code.lower();
        spot = text.lower().find(needle);
        if spot >= 0 {
            return (code, cut_span(text, spot, spot + len(needle)));
        }
    }
    return ("", text);
}


"""Working-time estimate stated in `text`, in minutes; 0 when absent."""
def:priv find_estimate(text: str) -> tuple[int, str] {
    hit = re.search(
        r"(?:~|about\s+|approx\.?\s+)?(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)\b",
        text,
        re.IGNORECASE
    );
    if hit is None {
        return (0, text);
    }
    amount = float(hit.group(1));
    unit = hit.group(2).lower();
    minutes = int(round(amount * 60.0)) if unit.startswith("h") else int(round(amount));
    if minutes < 5 or minutes > 1440 {
        return (0, text);
    }
    return (minutes, cut_span(text, hit.start(), hit.end()));
}


"""Time of day stated in `text` as HH:MM; empty string when absent."""
def:priv find_time(text: str) -> tuple[str, str] {
    noon = re.search(r"\bnoon\b", text, re.IGNORECASE);
    if noon is not None {
        return ("12:00", cut_span(text, noon.start(), noon.end()));
    }
    midnight = re.search(r"\bmidnight\b", text, re.IGNORECASE);
    if midnight is not None {
        return ("23:59", cut_span(text, midnight.start(), midnight.end()));
    }
    hit = re.search(
        r"\b(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)\b", text, re.IGNORECASE
    );
    if hit is None {
        hit = re.search(r"\b(\d{1,2}):(\d{2})\b", text);
    }
    if hit is None {
        return ("", text);
    }
    minutes = parse_clock(re.sub(r"[.\s]", "", hit.group(0)));
    if minutes < 0 {
        return ("", text);
    }
    hours = minutes // 60;
    mins = minutes % 60;
    return (f"{hours:02d}:{mins:02d}", cut_span(text, hit.start(), hit.end()));
}


"""Deadline stated in `text`, resolved against `today`; empty when absent."""
def:priv find_due_date(text: str, today: str) -> tuple[str, str] {
    iso = re.search(r"\b(\d{4}-\d{2}-\d{2})\b", text);
    if iso is not None {
        return (normalize_date(iso.group(1)), cut_span(text, iso.start(), iso.end()));
    }
    slashed = re.search(r"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b", text);
    if slashed is not None {
        resolved = month_day(today, int(slashed.group(1)), int(slashed.group(2)));
        if resolved {
            return (resolved, cut_span(text, slashed.start(), slashed.end()));
        }
    }
    named = re.search(
        r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})\b",
        text,
        re.IGNORECASE
    );
    if named is not None {
        resolved = month_day(
            today, month_index(named.group(1)), int(named.group(2))
        );
        if resolved {
            return (resolved, cut_span(text, named.start(), named.end()));
        }
    }
    today_cue = re.search(r"\b(today|tonight)\b", text, re.IGNORECASE);
    if today_cue is not None {
        return (today, cut_span(text, today_cue.start(), today_cue.end()));
    }
    tomorrow_cue = re.search(r"\b(tomorrow|tmrw|tmr)\b", text, re.IGNORECASE);
    if tomorrow_cue is not None {
        return (
            shift_days(today, 1),
            cut_span(text, tomorrow_cue.start(), tomorrow_cue.end())
        );
    }
    span = re.search(
        r"\bin\s+(\d{1,2})\s+(day|days|week|weeks)\b", text, re.IGNORECASE
    );
    if span is not None {
        count = int(span.group(1));
        step = 7 if span.group(2).lower().startswith("week") else 1;
        return (
            shift_days(today, count * step), cut_span(text, span.start(), span.end())
        );
    }
    next_week = re.search(r"\bnext\s+week\b", text, re.IGNORECASE);
    if next_week is not None {
        return (
            shift_days(today, 7), cut_span(text, next_week.start(), next_week.end())
        );
    }
    weekday = re.search(
        r"\b(?:next\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tues?|weds?|thurs?|fri|sat|sun)\b",
        text,
        re.IGNORECASE
    );
    if weekday is not None {
        resolved = next_weekday(today, weekday.group(1));
        if resolved {
            return (resolved, cut_span(text, weekday.start(), weekday.end()));
        }
    }
    return ("", text);
}


"""Priority stated in `text`; empty string when the student did not say."""
def:priv find_priority(text: str) -> tuple[str, str] {
    lowered = text.lower();
    for (label, cues) in [
        ("critical", CRITICAL_CUES),
        ("high", HIGH_CUES),
        ("low", LOW_CUES)
    ] {
        for cue in cues {
            spot = lowered.find(cue);
            if spot >= 0 {
                trimmed = cut_span(text, spot, spot + len(cue));
                return (label, re.sub(r"\bpriority\b", " ", trimmed, flags=re.IGNORECASE));
            }
        }
    }
    return ("", text);
}


"""Best guess at what sort of work `text` describes."""
def:priv find_kind(text: str) -> str {
    lowered = " " + text.lower() + " ";
    for (label, cues) in KIND_CUES {
        for cue in cues {
            if cue in lowered {
                return label;
            }
        }
    }
    return "task";
}


"""Strip leading and trailing filler so the remainder reads as a title."""
def:priv tidy_title(text: str) -> str {
    words = squeeze(text).split(" ");
    while words and words[0].lower() in FILLER_WORDS {
        words = words[1:];
    }
    while words and words[-1].lower() in FILLER_WORDS {
        words = words[:-1];
    }
    title = " ".join(words).strip(" -:,.");
    if not title {
        return "";
    }
    return title[0].upper() + title[1:];
}


"""A sensible urgency when the student did not state one."""
def:priv implied_priority(kind: str, due_date: str, today: str) -> str {
    if kind == "exam" {
        return "high";
    }
    if not due_date {
        return "low" if kind in ["personal", "social"] else "medium";
    }
    gap = days_between(today, due_date);
    if gap <= 1 {
        return "high";
    }
    if gap <= 3 and kind in ["assignment", "project"] {
        return "high";
    }
    return "medium";
}


"""Read a quick-capture line with regular expressions and a cue table.

This is the no-model path, and it is deliberately good enough to use on its
own: "EECS 449 project proposal due friday 5pm ~3h urgent" comes back fully
structured.
"""
def:priv heuristic_parse(
    capture: str, today: str, known_courses: list[str]
) -> ParsedTask {
    working = " " + (capture or "").strip() + " ";
    (course, working) = find_course(working, known_courses);
    (estimate, working) = find_estimate(working);
    (due_time, working) = find_time(working);
    (due_date, working) = find_due_date(working, today);
    (priority, working) = find_priority(working);
    kind = find_kind(capture);
    title = tidy_title(working) or squeeze(capture) or "Untitled task";
    if not priority {
        priority = implied_priority(kind, due_date, today);
    }
    if estimate <= 0 {
        estimate = DEFAULT_MINUTES.get(kind, 30);
    }
    return ParsedTask(
        title=title,
        kind=kind_enum(kind),
        priority=priority_enum(priority),
        due_date=due_date,
        due_time=due_time,
        estimate_minutes=estimate,
        course_code=course
    );
}


"""Split work into evenly paced sessions using a fixed stage template."""
def:priv heuristic_breakdown(total_minutes: int) -> list[Subtask] {
    budget = max(45, total_minutes);
    count = 3;
    if budget > 120 {
        count = 4;
    }
    if budget > 240 {
        count = 5;
    }
    if budget > 420 {
        count = 6;
    }
    stages = BREAKDOWN_STAGES[:count - 1] + [BREAKDOWN_STAGES[-1]];
    each = max(15, int(round(float(budget) / float(count) / 5.0)) * 5);
    return [Subtask(title=stage, estimate_minutes=each) for stage in stages];
}


"""Compose the briefing line from counts alone."""
def:priv heuristic_briefing(
    overdue: int, due_today: int, upcoming: int, load: int, capacity: int, top: str
) -> DayBriefing {
    if overdue > 0 {
        unit = "item" if overdue == 1 else "items";
        head = f"{overdue} overdue {unit}";
        tip = f"Clear the backlog before anything else -- start with {top}." if top else "Clear the backlog first.";
        return DayBriefing(headline=head, advice=tip);
    }
    if due_today > 0 {
        over = load > capacity;
        head = "Heavy day ahead" if over else "Focused day ahead";
        shape = "more than your capacity" if over else "comfortably inside your capacity";
        tip = f"{due_today} due today, {load} minutes of work -- {shape}.";
        if top {
            tip += f" Open with {top}.";
        }
        return DayBriefing(headline=head, advice=tip);
    }
    if upcoming > 0 {
        tip = f"Nothing is due today. Pull {top} forward and buy yourself slack later in the week." if top else "Nothing is due today -- pull upcoming work forward.";
        return DayBriefing(headline="Room to get ahead", advice=tip);
    }
    return DayBriefing(
        headline="All clear",
        advice="No open work on the board. Add what is on your mind, or take the afternoon back."
    );
}


# --- Entry points ------------------------------------------------------------
#
# Each of these tries the model, then falls back. `ai` on the result records
# which path actually ran, so the UI can be honest about it.

obj Interpretation {
    """A parsed capture plus whether a model produced it."""

    has parsed: ParsedTask = ParsedTask(),
        ai: bool = False;
}

obj BreakdownPlan {
    """Work sessions plus whether a model produced them."""

    has subtasks: list[Subtask] = [],
        ai: bool = False;
}

obj Briefing {
    """A day briefing plus whether a model produced it."""

    has headline: str = "",
        advice: str = "",
        ai: bool = False;
}


"""Sanity-check a model's parse before trusting it."""
def:priv parse_is_usable(parsed: ParsedTask, today: str, known_courses: list[str]) -> bool {
    if not parsed.title.strip() {
        return False;
    }
    if parsed.due_date {
        if not is_date(parsed.due_date) {
            return False;
        }
        # A model that resolved a relative date against the wrong "today" tends
        # to land a year off. Reject that rather than file work in the past.
        if days_between(today, parsed.due_date) < -1 {
            return False;
        }
    }
    if parsed.course_code and parsed.course_code not in known_courses {
        return False;
    }
    return 5 <= parsed.estimate_minutes <= 1440;
}


"""Read a free-text capture into a structured task."""
def:priv interpret(
    capture: str, today: str, weekday: str, known_courses: list[str]
) -> Interpretation {
    if ai_available() {
        try {
            parsed = ai_parse_task(capture, today, weekday, known_courses);
            if parse_is_usable(parsed, today, known_courses) {
                parsed.due_date = normalize_date(parsed.due_date);
                return Interpretation(parsed=parsed, ai=True);
            }
        } except Exception {}
    }
    return Interpretation(parsed=heuristic_parse(capture, today, known_courses), ai=False);
}


"""Split a large task into sequential work sessions."""
def:priv breakdown(
    title: str, notes: str, course: str, total_minutes: int, days_left: int
) -> BreakdownPlan {
    if ai_available() {
        try {
            steps = ai_breakdown(title, notes, course, total_minutes, days_left);
            clean = [
                Subtask(
                    title=s.title.strip(),
                    estimate_minutes=max(10, min(480, s.estimate_minutes))
                )
                for s in steps
                if s.title.strip()
            ];
            if 2 <= len(clean) <= 8 {
                return BreakdownPlan(subtasks=clean, ai=True);
            }
        } except Exception {}
    }
    return BreakdownPlan(subtasks=heuristic_breakdown(total_minutes), ai=False);
}


"""Write the one-line briefing above the agenda."""
def:priv briefing(
    context: str,
    overdue: int,
    due_today: int,
    upcoming: int,
    load: int,
    capacity: int,
    top: str
) -> Briefing {
    if ai_available() {
        try {
            note = ai_briefing(context);
            if note.headline.strip() and note.advice.strip() {
                return Briefing(
                    headline=note.headline.strip(),
                    advice=note.advice.strip(),
                    ai=True
                );
            }
        } except Exception {}
    }
    fallback = heuristic_briefing(overdue, due_today, upcoming, load, capacity, top);
    return Briefing(headline=fallback.headline, advice=fallback.advice, ai=False);
}
