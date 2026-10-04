"""Calendar arithmetic for the planner service.

Server-side only: it reaches for Python's `datetime`, which has no meaning in
a browser or React Native bundle. Clients receive dates already resolved to
ISO strings and never do date math themselves.
"""

import datetime;

glob WEEKDAY_NAMES: list[str] = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday"
];

glob MONTH_NAMES: list[str] = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
];


"""Today's date as YYYY-MM-DD."""
def:priv today_iso -> str {
    return datetime.date.today().isoformat();
}


"""Current UTC instant as an ISO-8601 string."""
def:priv now_iso -> str {
    return datetime.datetime.now(datetime.UTC).replace(tzinfo=None).isoformat() + "Z";
}


"""Minutes since local midnight."""
def:priv now_minutes -> int {
    now = datetime.datetime.now();
    return now.hour * 60 + now.minute;
}


"""Parse YYYY-MM-DD, tolerating an empty string or junk."""
def:priv parse_date(value: str) -> datetime.date | None {
    text = (value or "").strip();
    if not text {
        return None;
    }
    try {
        return datetime.date.fromisoformat(text[:10]);
    } except ValueError {
        return None;
    }
}


"""True when `value` is a parseable calendar date."""
def:priv is_date(value: str) -> bool {
    return parse_date(value) is not None;
}


"""Return a canonical YYYY-MM-DD, or an empty string when unparseable."""
def:priv normalize_date(value: str) -> str {
    parsed = parse_date(value);
    return parsed.isoformat() if parsed is not None else "";
}


"""`value` moved `delta` days, or the input unchanged if it is not a date."""
def:priv shift_days(value: str, delta: int) -> str {
    parsed = parse_date(value);
    if parsed is None {
        return value;
    }
    return (parsed + datetime.timedelta(days=delta)).isoformat();
}


"""Whole days from `start` to `end`; 0 when either side is unparseable."""
def:priv days_between(start: str, end: str) -> int {
    a = parse_date(start);
    b = parse_date(end);
    if a is None or b is None {
        return 0;
    }
    return (b - a).days;
}


""""Monday" ... "Sunday" for a date string."""
def:priv weekday_name(value: str) -> str {
    parsed = parse_date(value);
    if parsed is None {
        return "";
    }
    return WEEKDAY_NAMES[parsed.weekday()];
}


"""The Monday of the week containing `value`."""
def:priv week_start(value: str) -> str {
    parsed = parse_date(value);
    if parsed is None {
        return "";
    }
    return (parsed - datetime.timedelta(days=parsed.weekday())).isoformat();
}


""""Mon Oct 5" -- compact, human, and stable across locales."""
def:priv pretty_date(value: str) -> str {
    parsed = parse_date(value);
    if parsed is None {
        return "";
    }
    return (
        WEEKDAY_NAMES[parsed.weekday()][:3]
            + " "
            + MONTH_NAMES[parsed.month - 1]
            + " "
            + str(parsed.day)
    );
}


"""Minutes-from-midnight rendered as 24-hour HH:MM."""
def:priv clock(minutes: int) -> str {
    total = max(0, min(24 * 60 - 1, minutes));
    hours = total // 60;
    mins = total % 60;
    return f"{hours:02d}:{mins:02d}";
}


"""Minutes-from-midnight rendered as 9:30am."""
def:priv clock12(minutes: int) -> str {
    total = max(0, min(24 * 60 - 1, minutes));
    hours = total // 60;
    mins = total % 60;
    suffix = "am" if hours < 12 else "pm";
    display = hours % 12;
    if display == 0 {
        display = 12;
    }
    return f"{display}:{mins:02d}{suffix}";
}


"""Read "9", "9:30", "09:30", "9pm", "9:30 PM" into minutes from midnight.

Returns -1 when nothing time-like is present, which callers read as
"this task has no time of day".
"""
def:priv parse_clock(value: str) -> int {
    text = (value or "").strip().lower().replace(" ", "");
    if not text {
        return -1;
    }
    suffix = "";
    if text.endswith("am") or text.endswith("pm") {
        suffix = text[-2:];
        text = text[:-2];
    }
    parts = text.split(":");
    if not parts[0].isdigit() {
        return -1;
    }
    hours = int(parts[0]);
    mins = 0;
    if len(parts) > 1 and parts[1].isdigit() {
        mins = int(parts[1]);
    }
    if suffix == "pm" and hours < 12 {
        hours += 12;
    }
    if suffix == "am" and hours == 12 {
        hours = 0;
    }
    if hours > 23 or mins > 59 {
        return -1;
    }
    return hours * 60 + mins;
}


"""45 -> "45m";  150 -> "2h 30m";  120 -> "2h"."""
def:priv fmt_minutes(total: int) -> str {
    if total <= 0 {
        return "0m";
    }
    hours = total // 60;
    mins = total % 60;
    if hours == 0 {
        return f"{mins}m";
    }
    if mins == 0 {
        return f"{hours}h";
    }
    return f"{hours}h {mins}m";
}


""""today" / "tomorrow" / "in 3 days" / "4 days ago" / "Mon Oct 5"."""
def:priv relative_day(target: str, reference: str) -> str {
    if not is_date(target) {
        return "someday";
    }
    delta = days_between(reference, target);
    if delta == 0 {
        return "today";
    }
    if delta == 1 {
        return "tomorrow";
    }
    if delta == -1 {
        return "yesterday";
    }
    if 0 < delta <= 6 {
        return weekday_name(target);
    }
    if delta < 0 {
        return f"{-delta} days ago";
    }
    return pretty_date(target);
}


"""The next occurrence of a weekday name, strictly after `reference`."""
def:priv next_weekday(reference: str, target_name: str) -> str {
    start = parse_date(reference);
    if start is None {
        return "";
    }
    wanted = (target_name or "").strip().lower();
    index = -1;
    for (i, name) in enumerate(WEEKDAY_NAMES) {
        if name.lower() == wanted or name.lower()[:3] == wanted[:3] and len(wanted) >= 3 {
            index = i;
            break;
        }
    }
    if index < 0 {
        return "";
    }
    delta = (index - start.weekday()) % 7;
    if delta == 0 {
        delta = 7;
    }
    return (start + datetime.timedelta(days=delta)).isoformat();
}


"""Resolve a bare month/day to the next such date on or after `reference`."""
def:priv month_day(reference: str, month: int, day: int) -> str {
    base = parse_date(reference);
    if base is None or month < 1 or month > 12 or day < 1 or day > 31 {
        return "";
    }
    for year in [base.year, base.year + 1] {
        try {
            candidate = datetime.date(year, month, day);
        } except ValueError {
            continue;
        }
        if candidate >= base {
            return candidate.isoformat();
        }
    }
    return "";
}


"""Index of a month abbreviation ("oct" -> 10); 0 when unrecognized."""
def:priv month_index(name: str) -> int {
    wanted = (name or "").strip().lower()[:3];
    for (i, label) in enumerate(MONTH_NAMES) {
        if label.lower() == wanted {
            return i + 1;
        }
    }
    return 0;
}
