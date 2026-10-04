"""Quick capture -- the reason to reach for the phone at all.

Type one line, the server reads it, and the phone shows exactly how it was
understood so a bad guess is caught immediately.
"""

import from "@jac/mobui" { Pressable, ScrollView, Text, TextInput, View }

import from core.planner { QuickAddResult, quick_add, toggle_task }
import from mobile.components.TaskCard { TaskCard }
import from mobile.fmt { duration }
import from mobile.theme { C, styles }

glob EXAMPLES: list[str] = [
    "EECS 449 project proposal due friday 5pm ~3h urgent",
    "read chapter 7 for stats 415 by next tuesday 45m",
    "gym tomorrow 1h low priority"
];


def:pub Capture -> JsxElement {
    has text: str = "",
        busy: bool = False,
        captured: list[QuickAddResult] = [],
        error: str = "";

    async def submit {
        result: QuickAddResult = QuickAddResult();
        if not text.strip() or busy {
            return;
        }
        busy = True;
        error = "";
        try {
            result = await quick_add(text.strip());
        } except Exception {
            busy = False;
            error = "Cannot reach the planner service.";
            return;
        }
        busy = False;
        text = "";
        captured = [result] + captured;
    }

    async def complete(taskId: str) {
        try {
            await toggle_task(taskId);
        } except Exception {
            error = "Could not update that task.";
            return;
        }
        captured = [
            item for item in captured if item.task.id != taskId
        ];
    }

    return
        <ScrollView style={styles["screen"]} contentContainerStyle={styles["body"]}>
            <View style={styles["card"]}>
                <Text style={styles["headline"]}>Capture</Text>
                <Text style={styles["muted"]}>
                    One line. Course, deadline, length and urgency are read out
                    of the sentence.
                </Text>
                <TextInput
                    style={[styles["input"], {"minHeight": 76}]}
                    value={text}
                    placeholder="EECS 449 project proposal due friday 5pm ~3h urgent"
                    placeholderTextColor={C.faint}
                    multiline={True}
                    onChangeText={lambda (t: str) { text = t; }}
                />
                <Pressable style={styles["button"]} onPress={lambda { submit(); }}>
                    <Text style={styles["buttonText"]}>
                        {("Reading..." if busy else "Add to planner")}
                    </Text>
                </Pressable>
                {(
                    <View style={styles["banner"]}>
                        <Text style={styles["bannerText"]}>{error}</Text>
                    </View>
                ) if error else <View/>}
            </View>

            {(
                <View>
                    <Text style={styles["sectionTitle"]}>TRY ONE</Text>
                    <View style={styles["card"]}>
                        {[
                            <Pressable
                                key={sample}
                                onPress={lambda { text = sample; }}
                                style={{"paddingVertical": 6}}
                            >
                                <Text style={styles["muted"]}>{"“" + sample + "”"}</Text>
                            </Pressable> for sample in EXAMPLES
                        ]}
                    </View>
                </View>
            ) if len(captured) == 0 else <View/>}

            {(
                <View>
                    <Text style={styles["sectionTitle"]}>JUST CAPTURED</Text>
                    <View style={styles["cardTight"]}>
                        {[
                            <View key={item.task.id}>
                                <TaskCard
                                    task={item.task}
                                    onToggle={lambda { complete(item.task.id); }}
                                />
                                <View style={[styles["row"], {"paddingHorizontal": 12, "paddingBottom": 10}]}>
                                    <View style={[styles["pill"], styles["pillAccent"]] if item.ai else styles["pill"]}>
                                        <Text style={[styles["pillText"], styles["pillAccentText"]] if item.ai else styles["pillText"]}>
                                            {("ai" if item.ai else "parsed")}
                                        </Text>
                                    </View>
                                    <Text style={[styles["faint"], styles["grow"]]}>
                                        {item.interpreted}
                                    </Text>
                                </View>
                            </View> for item in captured
                        ]}
                    </View>
                </View>
            ) if len(captured) > 0 else <View/>}
        </ScrollView>;
}
