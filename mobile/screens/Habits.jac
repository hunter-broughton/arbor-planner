"""Habits -- tap to keep the streak alive."""

import from "@jac/mobui" { Pressable, ScrollView, Text, View }

import from core.planner { AgendaView, agenda, log_goal, unlog_goal }
import from mobile.theme { C, styles }


def:pub Habits -> JsxElement {
    has day: AgendaView = AgendaView(),
        loading: bool = True,
        error: str = "";

    async can with entry {
        await load();
    }

    async def load {
        fresh: AgendaView = AgendaView();
        try {
            fresh = await agenda("");
        } except Exception {
            loading = False;
            error = "Cannot reach the planner service.";
            return;
        }
        error = "";
        day = fresh;
        loading = False;
    }

    async def toggle(goalId: str, done: bool) {
        if done {
            await unlog_goal(goalId, "");
        } else {
            await log_goal(goalId, "");
        }
        await load();
    }

    if loading {
        return
            <View style={styles["empty"]}>
                <Text style={styles["emptyText"]}>Loading your habits...</Text>
            </View>;
    }

    kept = len([g for g in day.goals if g.done_this_period]);
    return
        <ScrollView style={styles["screen"]} contentContainerStyle={styles["body"]}>
            {(
                <View style={styles["banner"]}>
                    <Text style={styles["bannerText"]}>{error}</Text>
                </View>
            ) if error else <View/>}
            <View style={styles["card"]}>
                <Text style={styles["headline"]}>
                    {str(kept) + " of " + str(len(day.goals)) + " kept"}
                </Text>
                <Text style={styles["muted"]}>
                    Tap a habit to check it off for this period.
                </Text>
            </View>
            <View style={styles["cardTight"]}>
                {(
                    <View style={styles["empty"]}>
                        <Text style={styles["emptyText"]}>
                            No habits yet. Add some from the web app.
                        </Text>
                    </View>
                ) if len(day.goals) == 0 else (
                    <View>
                        {[
                            <Pressable
                                key={goal.id}
                                style={styles["taskRow"]}
                                onPress={lambda { toggle(goal.id, goal.done_this_period); }}
                            >
                                <View
                                    style={[styles["check"], styles["checkOn"]] if goal.done_this_period else styles["check"]}
                                >
                                    <Text style={styles["checkMark"]}>
                                        {"✓" if goal.done_this_period else " "}
                                    </Text>
                                </View>
                                <View style={styles["grow"]}>
                                    <Text style={styles["taskTitle"]}>{goal.title}</Text>
                                    <View style={styles["metaRow"]}>
                                        <View style={[styles["pill"], styles["pillOk"]] if goal.streak > 0 else styles["pill"]}>
                                            <Text style={[styles["pillText"], styles["pillOkText"]] if goal.streak > 0 else styles["pillText"]}>
                                                {str(goal.streak) + " streak"}
                                            </Text>
                                        </View>
                                        <Text style={styles["faint"]}>
                                            {str(goal.period_count) + "/" + str(goal.target_per_period) + " this " + ("week" if goal.cadence == "weekly" else "day")}
                                        </Text>
                                    </View>
                                    <View style={styles["streakStrip"]}>
                                        {[
                                            <View
                                                key={dayKey}
                                                style={[
                                                    styles["streakCell"],
                                                    {"backgroundColor": goal.color} if dayKey in goal.history else {}
                                                ]}
                                            /> for dayKey in day.recent_days
                                        ]}
                                    </View>
                                </View>
                            </Pressable> for goal in day.goals
                        ]}
                    </View>
                )}
            </View>
        </ScrollView>;
}
