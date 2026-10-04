"""One tappable task row. Tapping the box completes it."""

import from "@jac/mobui" { Pressable, Text, View }

import from core.contracts { TaskView }
import from mobile.fmt { due_label, duration }
import from mobile.theme { C, styles }


def:pub TaskCard(task: TaskView, onToggle: Callable[[], None]) -> JsxElement {
    duePill = styles["pill"];
    dueText = styles["pillText"];
    if task.days_until < 0 {
        duePill = [styles["pill"], styles["pillDanger"]];
        dueText = [styles["pillText"], styles["pillDangerText"]];
    } elif task.days_until == 0 {
        duePill = [styles["pill"], styles["pillWarn"]];
        dueText = [styles["pillText"], styles["pillWarnText"]];
    }
    return
        <View style={styles["taskRow"]}>
            <Pressable
                style={[styles["check"], styles["checkOn"]] if task.done else styles["check"]}
                onPress={onToggle}
            >
                <Text style={styles["checkMark"]}>{"✓" if task.done else " "}</Text>
            </Pressable>
            <View style={styles["grow"]}>
                <Text style={styles["taskTitleDone"] if task.done else styles["taskTitle"]}>
                    {task.title}
                </Text>
                <View style={styles["metaRow"]}>
                    {(
                        <View style={[styles["pill"], {"backgroundColor": task.course_color + "33"}]}>
                            <Text style={[styles["pillText"], {"color": task.course_color}]}>
                                {task.course_code}
                            </Text>
                        </View>
                    ) if task.course_code else <View/>}
                    <View style={duePill}>
                        <Text style={dueText}>{due_label(task)}</Text>
                    </View>
                    <Text style={styles["faint"]}>{duration(task.estimate_minutes)}</Text>
                    <Text style={styles["faint"]}>{task.priority}</Text>
                </View>
            </View>
        </View>;
}
