"""Design tokens and the one StyleSheet the mobile app renders through.

Typed `obj`s rather than dicts, so `C.accent` is an attribute the checker
verifies instead of a string key looked up at runtime.
"""

import from "@jac/mobui" { StyleSheet }

obj Colors {
    has bg: str = "#12141a",
        surface: str = "#1a1d25",
        surfaceAlt: str = "#212530",
        border: str = "#2c313d",
        text: str = "#e9e7e4",
        muted: str = "#a2a8b4",
        faint: str = "#6f7684",
        accent: str = "#3fb5a5",
        accentDim: str = "#16332f",
        danger: str = "#f0827c",
        dangerDim: str = "#3a1e1d",
        warn: str = "#e3a45d",
        warnDim: str = "#3a2a16",
        ok: str = "#7cc47f",
        okDim: str = "#1d2f1e";
}

obj Space {
    has xs: int = 4,
        sm: int = 8,
        md: int = 12,
        lg: int = 16,
        xl: int = 24;
}

obj Radii {
    has sm: int = 8,
        md: int = 12,
        lg: int = 18,
        pill: int = 999;
}

obj Fonts {
    has xs: int = 11,
        sm: int = 13,
        md: int = 15,
        lg: int = 19,
        xl: int = 26;
}

glob:pub C = Colors(),
     S = Space(),
     R = Radii(),
     F = Fonts();

glob:pub styles = StyleSheet.create(
    {
        "screen": {"flex": 1, "backgroundColor": C.bg},
        "body": {"padding": S.lg, "gap": S.md, "paddingBottom": 48},
        "header": {"paddingHorizontal": S.lg, "paddingTop": 52, "paddingBottom": S.md, "backgroundColor": C.surface, "borderBottomWidth": 1, "borderBottomColor": C.border},
        "headerRow": {"flexDirection": "row", "alignItems": "center", "justifyContent": "space-between"},
        "title": {"color": C.text, "fontSize": F.xl, "fontWeight": "bold"},
        "subtitle": {"color": C.muted, "fontSize": F.sm, "marginTop": 2},
        "sectionTitle": {"color": C.muted, "fontSize": F.xs, "fontWeight": "bold", "letterSpacing": 1, "marginBottom": S.sm, "marginTop": S.sm},
        "card": {"backgroundColor": C.surface, "borderRadius": R.md, "padding": S.lg, "gap": S.sm, "borderWidth": 1, "borderColor": C.border},
        "cardTight": {"backgroundColor": C.surface, "borderRadius": R.md, "borderWidth": 1, "borderColor": C.border, "overflow": "hidden"},
        "row": {"flexDirection": "row", "alignItems": "center", "gap": S.sm},
        "rowBetween": {"flexDirection": "row", "alignItems": "center", "justifyContent": "space-between", "gap": S.sm},
        "grow": {"flex": 1},
        "text": {"color": C.text, "fontSize": F.md},
        "muted": {"color": C.muted, "fontSize": F.sm},
        "faint": {"color": C.faint, "fontSize": F.xs},
        "headline": {"color": C.text, "fontSize": F.lg, "fontWeight": "bold"},
        "taskRow": {"flexDirection": "row", "alignItems": "flex-start", "gap": S.md, "padding": S.md, "borderBottomWidth": 1, "borderBottomColor": C.border},
        "check": {"width": 24, "height": 24, "borderRadius": R.sm, "borderWidth": 2, "borderColor": C.faint, "alignItems": "center", "justifyContent": "center"},
        "checkOn": {"backgroundColor": C.accent, "borderColor": C.accent},
        "checkMark": {"color": C.bg, "fontSize": F.sm, "fontWeight": "bold"},
        "taskTitle": {"color": C.text, "fontSize": F.md, "fontWeight": "600"},
        "taskTitleDone": {"color": C.faint, "fontSize": F.md, "textDecorationLine": "line-through"},
        "metaRow": {"flexDirection": "row", "alignItems": "center", "gap": S.sm, "marginTop": S.xs, "flexWrap": "wrap"},
        "pill": {"paddingHorizontal": S.sm, "paddingVertical": 2, "borderRadius": R.pill, "backgroundColor": C.surfaceAlt},
        "pillText": {"color": C.muted, "fontSize": F.xs, "fontWeight": "600"},
        "pillAccent": {"backgroundColor": C.accentDim},
        "pillAccentText": {"color": C.accent},
        "pillDanger": {"backgroundColor": C.dangerDim},
        "pillDangerText": {"color": C.danger},
        "pillWarn": {"backgroundColor": C.warnDim},
        "pillWarnText": {"color": C.warn},
        "pillOk": {"backgroundColor": C.okDim},
        "pillOkText": {"color": C.ok},
        "input": {"backgroundColor": C.surfaceAlt, "borderRadius": R.sm, "borderWidth": 1, "borderColor": C.border, "paddingHorizontal": S.md, "paddingVertical": S.md, "color": C.text, "fontSize": F.md},
        "button": {"backgroundColor": C.accent, "borderRadius": R.sm, "paddingVertical": S.md, "paddingHorizontal": S.lg, "alignItems": "center"},
        "buttonText": {"color": "#08211e", "fontSize": F.md, "fontWeight": "bold"},
        "buttonGhost": {"backgroundColor": C.surfaceAlt, "borderRadius": R.sm, "paddingVertical": S.sm, "paddingHorizontal": S.md, "alignItems": "center", "borderWidth": 1, "borderColor": C.border},
        "buttonGhostText": {"color": C.text, "fontSize": F.sm, "fontWeight": "600"},
        "tabBar": {"flexDirection": "row", "backgroundColor": C.surface, "borderTopWidth": 1, "borderTopColor": C.border, "paddingBottom": 22, "paddingTop": S.sm},
        "tab": {"flex": 1, "alignItems": "center", "paddingVertical": S.sm, "gap": 2},
        "tabLabel": {"color": C.faint, "fontSize": F.xs, "fontWeight": "600"},
        "tabLabelOn": {"color": C.accent, "fontSize": F.xs, "fontWeight": "bold"},
        "tabGlyph": {"fontSize": 18},
        "meterTrack": {"height": 8, "borderRadius": R.pill, "backgroundColor": C.surfaceAlt, "overflow": "hidden"},
        "meterFill": {"height": 8, "borderRadius": R.pill, "backgroundColor": C.accent},
        "meterFillOver": {"backgroundColor": C.warn},
        "empty": {"padding": S.xl, "alignItems": "center"},
        "emptyText": {"color": C.faint, "fontSize": F.sm, "textAlign": "center"},
        "banner": {"backgroundColor": C.dangerDim, "borderRadius": R.sm, "padding": S.md},
        "bannerText": {"color": C.danger, "fontSize": F.sm},
        "slot": {"flexDirection": "row", "gap": S.md, "padding": S.md, "borderBottomWidth": 1, "borderBottomColor": C.border},
        "slotTime": {"color": C.muted, "fontSize": F.xs, "width": 74},
        "slotBar": {"width": 3, "borderRadius": R.pill, "backgroundColor": C.accent},
        "slotBarBreak": {"backgroundColor": C.border},
        "streakStrip": {"flexDirection": "row", "gap": 3, "marginTop": S.sm},
        "streakCell": {"width": 12, "height": 12, "borderRadius": 3, "backgroundColor": C.surfaceAlt},
        "authWrap": {"flex": 1, "backgroundColor": C.bg, "justifyContent": "center", "padding": S.xl, "gap": S.md},
        "glyph": {"width": 44, "height": 44, "borderRadius": R.md, "backgroundColor": C.accent, "alignItems": "center", "justifyContent": "center"},
        "glyphText": {"color": "#08211e", "fontSize": F.lg, "fontWeight": "bold"}
    }
);
