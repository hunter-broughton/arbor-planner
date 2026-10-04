"""Display helpers for the mobile bundle -- pure string and integer work."""

import from core.contracts { NO_DUE_DATE, TaskView }


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


"""A due date phrased relative to today."""
def:pub due_label(task: TaskView) -> str {
    if task.days_until == NO_DUE_DATE {
        return "someday";
    }
    if task.days_until < 0 {
        return "overdue " + str(-task.days_until) + "d";
    }
    if task.days_until == 0 {
        return "today";
    }
    if task.days_until == 1 {
        return "tomorrow";
    }
    return "in " + str(task.days_until) + "d";
}
