"""Arbor for phones -- a mobUI client of the same planner service.

No store of its own and no duplicated rules: every screen bridges to the
`planner` service app, so a task completed here is completed in the browser
and in the terminal. Built entirely from `@jac/mobui` primitives, so the same
source compiles to React Native for a device and to react-native-web for the
browser preview.
"""

import from "@jac/mobui" { Pressable, Text, View } 
import from "@jac/runtime" { jacIsLoggedIn, jacLogout }

import from mobile.screens.Capture { Capture }
import from mobile.screens.Habits { Habits }
import from mobile.screens.SignIn { SignIn }
import from mobile.screens.Today { Today }
import from mobile.theme { C, styles }

glob TABS: list[tuple[str, str, str]] = [
    ("today", "Today", "◎"),
    ("capture", "Capture", "＋"),
    ("habits", "Habits", "◆")
];


def:pub app -> JsxElement {
    has signedIn: bool = False,
        checking: bool = True,
        tab: str = "today";

    can with entry {
        signedIn = jacIsLoggedIn();
        checking = False;
    }

    def signOut {
        jacLogout();
        signedIn = False;
        tab = "today";
    }

    if checking {
        return
            <View style={styles["empty"]}>
                <Text style={styles["emptyText"]}>Starting Arbor...</Text>
            </View>;
    }

    if not signedIn {
        return <SignIn onSignedIn={lambda { signedIn = True; }}/>;
    }

    return
        <View style={styles["screen"]}>
            <View style={styles["header"]}>
                <View style={styles["headerRow"]}>
                    <View style={styles["row"]}>
                        <View style={[styles["glyph"], {"width": 30, "height": 30}]}>
                            <Text style={[styles["glyphText"], {"fontSize": 15}]}>A</Text>
                        </View>
                        <View>
                            <Text style={[styles["title"], {"fontSize": 20}]}>Arbor</Text>
                            <Text style={styles["subtitle"]}>your planner, everywhere</Text>
                        </View>
                    </View>
                    <Pressable style={styles["buttonGhost"]} onPress={signOut}>
                        <Text style={styles["buttonGhostText"]}>Sign out</Text>
                    </Pressable>
                </View>
            </View>

            <View style={styles["grow"]}>
                {(
                    <Today/>
                ) if tab == "today" else (
                    <Capture/> if tab == "capture" else <Habits/>
                )}
            </View>

            <View style={styles["tabBar"]}>
                {[
                    <Pressable
                        key={key}
                        style={styles["tab"]}
                        onPress={lambda { tab = key; }}
                    >
                        <Text
                            style={[
                                styles["tabGlyph"],
                                {"color": C.accent if tab == key else C.faint}
                            ]}
                        >
                            {glyph}
                        </Text>
                        <Text style={styles["tabLabelOn"] if tab == key else styles["tabLabel"]}>
                            {label}
                        </Text>
                    </Pressable> for (key, label, glyph) in TABS
                ]}
            </View>
        </View>;
}
