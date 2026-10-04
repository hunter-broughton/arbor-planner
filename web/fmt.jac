"""Display helpers for the browser.

These run in the client bundle, so they are pure Jac over plain strings and
integers -- no `datetime`, no server calls. Anything that needs a real
calendar is computed on the server and arrives pre-resolved.
"""

import from core.contracts { NO_DUE_DATE, TaskView }

glob PRIORITY_CLASS: dict[str, str] = {
    "critical": "pill pill-danger",
    "high": "pill pill-warn",
    "medium": "pill",
    "low": "pill"
};


"""Minutes as "2h 30m"."""
def:pub duration(total: int) -> str {
    if total <= 0 {
        return "0m";
    }
    hours = total // 60;
    mins = total % 60;
    if hours == 0 {
        return str(mins) + "m";
    }
    if mins == 0 {
        return str(hours) + "h";
    }
    return str(hours) + "h " + str(mins) + "m";
}


"""Minutes from midnight as "9:30am"."""
def:pub clock(minutes: int) -> str {
    hours = minutes // 60;
    mins = minutes % 60;
    suffix = "am" if hours < 12 else "pm";
    shown = hours % 12;
    if shown == 0 {
        shown = 12;
    }
    padded = ("0" + str(mins)) if mins < 10 else str(mins);
    return str(shown) + ":" + padded + suffix;
}


"""A due date phrased relative to today: "overdue 2d", "today", "in 4d"."""
def:pub due_label(task: TaskView) -> str {
    if task.days_until == NO_DUE_DATE {
        return "no deadline";
    }
    if task.days_until < 0 {
        return "overdue " + str(-task.days_until) + "d";
    }
    if task.days_until == 0 {
        return "today" + ((" " + clock_from_text(task.due_time)) if task.due_time else "");
    }
    if task.days_until == 1 {
        return "tomorrow";
    }
    return "in " + str(task.days_until) + "d";
}


"""Turn a stored "HH:MM" into "5:00pm"; passes junk straight through."""
def:pub clock_from_text(value: str) -> str {
    parts = value.split(":");
    if len(parts) != 2 {
        return value;
    }
    try {
        return clock(int(parts[0]) * 60 + int(parts[1]));
    } except Exception {
        return value;
    }
}


"""The CSS class for a due-date pill, so overdue work reads as red."""
def:pub due_class(task: TaskView) -> str {
    if task.days_until == NO_DUE_DATE {
        return "pill";
    }
    if task.days_until < 0 {
        return "pill pill-danger";
    }
    if task.days_until == 0 {
        return "pill pill-warn";
    }
    return "pill";
}


"""The CSS class for a priority pill."""
def:pub priority_class(priority: str) -> str {
    return PRIORITY_CLASS.get(priority, "pill");
}


""""3 tasks" / "1 task"."""
def:pub plural(count: int, word: str) -> str {
    return str(count) + " " + word + ("" if count == 1 else "s");
}


"""The day-of-month from an ISO date, for the week grid."""
def:pub day_of_month(date: str) -> str {
    parts = date.split("-");
    if len(parts) != 3 {
        return date;
    }
    return parts[2].lstrip("0") or parts[2];
}
