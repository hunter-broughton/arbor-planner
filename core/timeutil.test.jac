"""Calendar arithmetic -- the layer everything else trusts."""

test "iso dates round-trip and shift" {
    assert normalize_date("2026-10-04") == "2026-10-04";
    assert normalize_date("not a date") == "";
    assert normalize_date("") == "";
    assert shift_days("2026-10-04", 1) == "2026-10-05";
    assert shift_days("2026-10-04", -4) == "2026-09-30";
    assert shift_days("2026-12-31", 1) == "2027-01-01";
}

test "days_between is signed and handles month ends" {
    assert days_between("2026-10-04", "2026-10-09") == 5;
    assert days_between("2026-10-09", "2026-10-04") == -5;
    assert days_between("2026-09-30", "2026-10-01") == 1;
    assert days_between("bogus", "2026-10-01") == 0;
}

test "weekday and week_start agree" {
    assert weekday_name("2026-10-04") == "Sunday";
    assert week_start("2026-10-04") == "2026-09-28";
    assert weekday_name(week_start("2026-10-04")) == "Monday";
}

test "next_weekday always lands strictly ahead" {
    # 2026-10-04 is a Sunday.
    assert next_weekday("2026-10-04", "friday") == "2026-10-09";
    assert next_weekday("2026-10-04", "mon") == "2026-10-05";
    assert next_weekday("2026-10-04", "sunday") == "2026-10-11";
    assert next_weekday("2026-10-04", "noneday") == "";
}

test "month_day rolls into next year when the date has passed" {
    assert month_day("2026-10-04", 10, 9) == "2026-10-09";
    assert month_day("2026-10-04", 1, 15) == "2027-01-15";
    assert month_day("2026-10-04", 2, 30) == "";
    assert month_index("Oct") == 10;
    assert month_index("february") == 2;
    assert month_index("zzz") == 0;
}

test "clocks parse and render both ways" {
    assert parse_clock("5pm") == 1020;
    assert parse_clock("09:30") == 570;
    assert parse_clock("12am") == 0;
    assert parse_clock("12pm") == 720;
    assert parse_clock("") == -1;
    assert parse_clock("99:99") == -1;
    assert clock(570) == "09:30";
    assert clock12(1020) == "5:00pm";
    assert clock12(0) == "12:00am";
}

test "durations read the way a person would say them" {
    assert fmt_minutes(45) == "45m";
    assert fmt_minutes(60) == "1h";
    assert fmt_minutes(150) == "2h 30m";
    assert fmt_minutes(0) == "0m";
}

test "relative_day names near dates and falls back to a calendar date" {
    today = "2026-10-04";
    assert relative_day(today, today) == "today";
    assert relative_day("2026-10-05", today) == "tomorrow";
    assert relative_day("2026-10-03", today) == "yesterday";
    assert relative_day("2026-10-08", today) == "Thursday";
    assert relative_day("2026-09-28", today) == "6 days ago";
    assert relative_day("", today) == "someday";
    assert pretty_date("2026-10-04") == "Sun Oct 4";
}
