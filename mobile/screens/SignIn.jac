"""Phone sign-in. Same accounts, same graph, same server as the web app."""

import from "@jac/mobui" { Pressable, Text, TextInput, View }
import from "@jac/runtime" { SignupResult, jacLogin, jacSignup }

import from mobile.theme { C, F, styles }


def:pub SignIn(onSignedIn: Callable[[], None]) -> JsxElement {
    has username: str = "",
        password: str = "",
        creating: bool = False,
        busy: bool = False,
        error: str = "";

    async def submit {
        signup: SignupResult | None = None;
        ok: bool = False;
        if not username.strip() or not password {
            error = "Enter a username and a password.";
            return;
        }
        busy = True;
        error = "";
        try {
            if creating {
                signup = await jacSignup(username.strip(), password);
                if not signup.success {
                    busy = False;
                    error = str(signup.error) or "That username is taken.";
                    return;
                }
            }
            ok = await jacLogin(username.strip(), password);
        } except Exception {
            busy = False;
            error = "Could not reach the planner service.";
            return;
        }
        busy = False;
        if ok {
            onSignedIn();
        } else {
            error = "Those credentials did not work.";
        }
    }

    return
        <View style={styles["authWrap"]}>
            <View style={styles["brandRow"]}>
                <Text style={[styles["brandBracket"], {"fontSize": F.xl}]}>&lt;</Text>
                <Text style={[styles["brandOne"], {"fontSize": F.xl}]}>Hunter</Text>
                <Text style={[styles["brandSlash"], {"fontSize": F.xl}]}>/</Text>
                <Text style={[styles["brandTwo"], {"fontSize": F.xl}]}>Plan</Text>
                <Text style={[styles["brandBracket"], {"fontSize": F.xl}]}>&gt;</Text>
            </View>
            <Text style={styles["subtitle"]}>
                {("Create an account to start planning." if creating else "Sign in to your planner.")}
            </Text>
            {(
                <View style={styles["banner"]}>
                    <Text style={styles["bannerText"]}>{error}</Text>
                </View>
            ) if error else <View/>}
            <TextInput
                style={styles["input"]}
                value={username}
                placeholder="username"
                placeholderTextColor={C.faint}
                autoCapitalize="none"
                onChangeText={lambda (t: str) { username = t; }}
            />
            <TextInput
                style={styles["input"]}
                value={password}
                placeholder="password"
                placeholderTextColor={C.faint}
                secureTextEntry={True}
                autoCapitalize="none"
                onChangeText={lambda (t: str) { password = t; }}
            />
            <Pressable style={styles["button"]} onPress={lambda { submit(); }}>
                <Text style={styles["buttonText"]}>
                    {(
                        "Working..."
                            if busy
                            else ("Create account" if creating else "Sign in")
                    )}
                </Text>
            </Pressable>
            <Pressable
                onPress={lambda {
                    creating = not creating;
                    error = "";
                }}
            >
                <Text style={[styles["muted"], {"textAlign": "center"}]}>
                    {(
                        "Already have an account? Sign in"
                            if creating
                            else "New here? Create an account"
                    )}
                </Text>
            </Pressable>
        </View>;
}
