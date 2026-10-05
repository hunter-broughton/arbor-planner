"""Today on the phone: the briefing, what is due, and the day's blocks.

Exactly one call fills this screen -- the same `agenda()` the web app uses,
assembled by the same walker over the same graph.
"""

import from "@jac/mobui" { Pressable, ScrollView, Text, View }

import from core.planner {
    AgendaView,
    PlanResult,
    agenda,
    get_day_plan,
    plan_day,
    toggle_task
}
import from mobile.components.TaskCard { TaskCard }
import from mobile.fmt { clock, duration }
import from mobile.theme { C, styles }


def:pub Today -> JsxElement {
    has day: AgendaView = AgendaView(),
        plan: PlanResult = PlanResult(),
        loading: bool = True,
        planning: bool = False,
        error: str = "";

    async can with entry {
        await load();
    }

    async def load {
        freshDay: AgendaView = AgendaView();
        freshPlan: PlanResult = PlanResult();
        try {
            freshDay = await agenda("");
            freshPlan = await get_day_plan("");
        } except Exception {
            loading = False;
            error = "Cannot reach the planner service.";
            return;
        }
        error = "";
        day = freshDay;
        plan = freshPlan;
        loading = False;
    }

    async def toggle(taskId: str) {
        await toggle_task(taskId);
        await load();
    }

    async def build {
        fresh: PlanResult = PlanResult();
        planning = True;
        try {
            fresh = await plan_day("", 0);
        } except Exception {
            planning = False;
            error = "Could not build a plan.";
            return;
        }
        plan = fresh;
        planning = False;
    }

    if loading {
        return
            <View style={styles["empty"]}>
                <Text style={styles["emptyText"]}>Loading your day...</Text>
            </View>;
    }

    focus = day.overdue + day.due_today;
    capacity = max(1, day.capacity_minutes);
    fillWidth = str(min(100, int(float(day.load_minutes) * 100.0 / float(capacity)))) + "%";
    return
        <ScrollView style={styles["screen"]} contentContainerStyle={styles["body"]}>
            {(
                <View style={styles["banner"]}>
                    <Text style={styles["bannerText"]}>{error}</Text>
                </View>
            ) if error else <View/>}

            <View style={styles["card"]}>
                <Text style={styles["headline"]}>{day.headline or "Your day"}</Text>
                <Text style={styles["muted"]}>{day.advice}</Text>
                <View style={styles["meterTrack"]}>
                    <View
                        style={[
                            styles["meterFill"],
                            styles["meterFillOver"] if day.load_minutes > capacity else {},
                            {"width": fillWidth}
                        ]}
                    />
                </View>
                <View style={styles["rowBetween"]}>
                    <Text style={styles["faint"]}>
                        {duration(day.load_minutes) + " of " + duration(day.capacity_minutes)}
                    </Text>
                    <View style={[styles["pill"], styles["pillAccent"]] if day.ai else styles["pill"]}>
                        <Text style={[styles["pillText"], styles["pillAccentText"]] if day.ai else styles["pillText"]}>
                            {("ai briefing" if day.ai else "rule-based")}
                        </Text>
                    </View>
                </View>
            </View>

            <Text style={styles["sectionTitle"]}>ON DECK</Text>
            <View style={styles["cardTight"]}>
                {(
                    <View style={styles["empty"]}>
                        <Text style={styles["emptyText"]}>
                            Nothing overdue or due today. Nice.
                        </Text>
                    </View>
                ) if len(focus) == 0 else (
                    <View>
                        {[
                            <TaskCard
                                key={task.id}
                                task={task}
                                onToggle={lambda { toggle(task.id); }}
                            /> for task in focus
                        ]}
                    </View>
                )}
            </View>

            <View style={styles["rowBetween"]}>
                <Text style={styles["sectionTitle"]}>DAY PLAN</Text>
                <Pressable style={styles["buttonGhost"]} onPress={lambda { build(); }}>
                    <Text style={styles["buttonGhostText"]}>
                        {(
                            "Planning..."
                                if planning
                                else ("Replan" if len(plan.blocks) > 0 else "Build plan")
                        )}
                    </Text>
                </Pressable>
            </View>
            <View style={styles["cardTight"]}>
                {(
                    <View style={styles["empty"]}>
                        <Text style={styles["emptyText"]}>
                            No schedule yet. Build one and HunterPlan lays your open
                            work into focus blocks.
                        </Text>
                    </View>
                ) if len(plan.blocks) == 0 else (
                    <View>
                        {[
                            <View key={block.id} style={styles["slot"]}>
                                <Text style={styles["slotTime"]}>
                                    {clock(block.start_min)}
                                </Text>
                                <View
                                    style={[styles["slotBar"], styles["slotBarBreak"]] if block.kind == "break" else styles["slotBar"]}
                                />
                                <View style={styles["grow"]}>
                                    <Text style={styles["taskTitle"] if block.kind == "focus" else styles["muted"]}>
                                        {block.label}
                                    </Text>
                                    <Text style={styles["faint"]}>
                                        {block.rationale}
                                    </Text>
                                </View>
                            </View> for block in plan.blocks
                        ]}
                    </View>
                )}
            </View>

            <Text style={styles["sectionTitle"]}>COMING UP</Text>
            <View style={styles["cardTight"]}>
                {(
                    <View style={styles["empty"]}>
                        <Text style={styles["emptyText"]}>Nothing on the horizon.</Text>
                    </View>
                ) if len(day.upcoming) == 0 else (
                    <View>
                        {[
                            <TaskCard
                                key={task.id}
                                task={task}
                                onToggle={lambda { toggle(task.id); }}
                            /> for task in day.upcoming
                        ]}
                    </View>
                )}
            </View>
        </ScrollView>;
}
