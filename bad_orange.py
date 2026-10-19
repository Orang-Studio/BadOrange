#!/usr/bin/env python3
'''The Bad Orange, Bad Apple played on KDE popups.
    Credits to Vakarux, nomico, adasjusk, {Enderman for inspiration}
    python3 bad_orange.py      
    python3 bad_orange.py --now
'''
import argparse, hashlib, json, os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))          
TRACK = os.path.join(HERE, "bad_apple.wav")
CUES = os.path.join(HERE, "cues.json")
ICONS_BACKUP = os.path.join(HERE, "icons_backup.json")
WINDOW_ICON = os.path.join(HERE, "the_evil.png")
LEAD = 0.03
PONG_FRAME = 0.05

ICONS_JS = r"""
var mode = %s, saved = %s, files = %s, at = %s, frame = %s, out = {};
desktops().forEach(function (d) {
    if (d.type !== "org.kde.plasma.folder") return;
    var g = screenGeometry(d.screen);
    if (mode === "pong" && (g.x !== at[0] || g.y !== at[1])) return;   // only the show's screen
    d.currentConfigGroup = ["General"];
    if (mode === "save") {
        out[d.id] = {positions: String(d.readConfig("positions")),
                     changedPositions: String(d.readConfig("changedPositions"))};
        return;
    }

    

    if (mode === "restore") {
        var s = saved[d.id];
        if (!s) return;
        d.writeConfig("positions", s.positions);
        d.writeConfig("changedPositions", s.changedPositions);
    } else {
        var all = JSON.parse(saved[d.id] ? saved[d.id].positions : String(d.readConfig("positions")) || "{}");
        var res = String(d.readConfig("lastResolution")), p = all[res];
        if (!p) return;
        var wh = res.split("x"), cell = cellSize(d), w = +wh[0], h = +wh[1];
        panels().forEach(function (pl) {   // the grid only covers what panels leave free
            if (pl.screen !== d.screen || pl.hiding !== "none") return;
            if (pl.location === "top" || pl.location === "bottom") h -= pl.height; else w -= pl.height;
        });
        var cols = Math.floor(w / cell[0]), rows = Math.floor(h / cell[1]), byCol = cfg(d, "arrangement", 0) == 1;
        var mine = [], here = files[d.screen] || files.all;   // files on this screen (the list also keeps long-gone ones)
        
        for (var i = 2; i < p.length; i += 3) if (here.indexOf(p[i]) >= 0) mine.push(i);
        var pong = mode === "pong" && mine.length >= 3 && pongLayout(mine.length, cols, rows, frame);
        
        if (mode === "pong" && !pong) return;
        var free = [];
        for (var c = 0; c < cols * rows; c++) free.push(c);
        mine.forEach(function (i, k) {
            var col, row;
            
            if (pong) {
                col = pong[k][0]; row = pong[k][1];
            } else if (mode === "scatter") {
                var c = free.splice(Math.floor(Math.random() * free.length), 1)[0];
                col = c %% cols; row = Math.floor(c / cols);
            } else if (mode === "flip") {      // turn the desktop upside down
                col = cols - 1 - Number(p[byCol ? i + 1 : i + 2]); row = rows - 1 - Number(p[byCol ? i + 2 : i + 1]);
            } else {                           // circle
                var a = k / mine.length * 2 * Math.PI;
                col = Math.round((cols - 1) / 2 * (1 + 0.85 * Math.cos(a)));
                row = Math.round((rows - 1) / 2 * (1 + 0.85 * Math.sin(a)));
            }
            col = Math.max(0, Math.min(cols - 1, col)); row = Math.max(0, Math.min(rows - 1, row));
            p[i + 1] = String(byCol ? col : row);      // entries are [stripe, slot], stripes are rows or columns
            p[i + 2] = String(byCol ? row : col);
        });
        p[0] = String(byCol ? cols : rows); p[1] = String(byCol ? rows : cols);
        d.writeConfig("positions", JSON.stringify(all));
    }
    var size = d.readConfig("iconSize");
    
    if (size === "" || size === undefined) size = 3;
    d.writeConfig("iconSize", size == 1 ? 2 : 1); d.reloadConfig();
    d.writeConfig("iconSize", size); d.reloadConfig();
});

if (mode === "save") print(JSON.stringify(out));

function cfg(d, key, def) {
    var v = d.readConfig(key);
    return v === "" || v === undefined ? def : Number(v);
}

function cellSize(d) {
    var icon = [22, 32, 48, 64, 96, 128, 256][cfg(d, "iconSize", 3)], unit = 18, spacing = 4;
    return [Math.max(icon + 2 * unit + 2 * spacing, 16 * (cfg(d, "labelWidth", 1) * 2 + 4)), icon + unit * cfg(d, "textLines", 2) + 3 * spacing];
}

function pongLayout(n, cols, rows, t) {
    var pad = Math.min(3, Math.floor((n - 1) / 2)), bs = n - 2 * pad >= 4 && pad >= 2 ? 2 : 1;
    var rest = n - 2 * pad - bs * bs, top = Math.ceil(rest / cols), out = [];
    
    if (cols < bs + 4 || rows - top < Math.max(pad, bs) + 1) return null;   // no room to play
    
    function tri(lo, hi) {
        var span = Math.max(1, hi - lo), m = t %% (2 * span);
        return lo + (m <= span ? m : 2 * span - m);
    }
    
    var bx = tri(1, cols - 1 - bs), by = tri(top, rows - bs);
    var py = Math.max(top, Math.min(rows - pad, by + Math.floor((bs - pad) / 2)));
    
    for (var i = 0; i < pad; i++) out.push([0, py + i], [cols - 1, py + i]);
    for (var i = 0; i < bs * bs; i++) out.push([bx + i %% bs, by + Math.floor(i / bs)]);
    for (var i = 0; i < rest; i++) out.push([i %% cols, Math.floor(i / cols)]);
    return out;
}
"""



def desktop_files():
    desk = subprocess.run(["xdg-user-dir", "DESKTOP"], capture_output=True, text=True).stdout.strip() \
        or os.path.expanduser("~/Desktop")
    out = {"all": ["desktop:/" + f for f in os.listdir(desk)] if os.path.isdir(desk) else []}
    
    try:
        rc = open(os.path.expanduser("~/.config/plasma-org.kde.plasma.desktop-appletsrc")).read()
        m = re.search(r"^screenMapping=(.*)$", rc, re.M).group(1).split(",")
    except (OSError, AttributeError):
        return out
   
    for url, screen in zip(m[0::3], m[1::3]):
        if url in out["all"]:
            out.setdefault(screen, []).append(url)
    return out


def icons(mode, saved=None, at=(0, 0), frame=0):
    js = ICONS_JS % (json.dumps(mode), json.dumps(saved or {}), json.dumps(desktop_files()), json.dumps(list(at)), int(frame))
    
    try:
        r = subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def restore_icons():
    if not os.path.exists(ICONS_BACKUP):
        return
    
    if icons("restore", json.load(open(ICONS_BACKUP))) is not None:
        os.remove(ICONS_BACKUP)
    else:
        print(f"couldnt reach plasmashell for restoring desktop icons, {ICONS_BACKUP}")

RUNNER_CPP = r"""
#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QSurfaceFormat>

int main(int argc, char **argv) {
    QSurfaceFormat f = QSurfaceFormat::defaultFormat();
    f.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(f);
    QApplication app(argc, argv);
    app.setWindowIcon(QIcon(app.arguments().at(1)));
    QQmlApplicationEngine engine(QUrl::fromLocalFile(app.arguments().at(2)));
    return engine.rootObjects().isEmpty() ? 1 : app.exec();

}
"""


def runner():
    # Build runner into ~/.cache
    exe = os.path.expanduser(f"~/.cache/bad_orange/runner-{hashlib.sha1(RUNNER_CPP.encode()).hexdigest()[:8]}")
    
    if os.path.exists(exe):
        return exe
    os.makedirs(os.path.dirname(exe), exist_ok=True)
    print("building the window runner (once)...")
    
    try:
        flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Widgets", "Qt6Qml"], text=True).split()
        subprocess.run(["g++", "-std=c++17", "-fPIC", "-x", "c++", "-", "-o", exe, *flags], input=RUNNER_CPP, text=True, check=True)
        return exe
    except (OSError, subprocess.CalledProcessError):
        return None


def pick_screen(name=None):
    
    outs = [o for o in json.loads(subprocess.check_output(["kscreen-doctor", "-j"]))["outputs"]
            if o.get("enabled") and o.get("connected")]
    
    if name:
        outs = [o for o in outs if o["name"] == name] or sys.exit(f"no enabled output named {name}")
    o = min(outs, key=lambda o: o.get("priority", 99))
    mode = next(m for m in o["modes"] if m["id"] == o["currentModeId"])
    w, h = mode["size"]["width"], mode["size"]["height"]
    
    if o.get("rotation") in (2, 8):   # left / right
        w, h = h, w
    s = o.get("scale", 1) or 1
    return o["name"], o["pos"]["x"], o["pos"]["y"], round(w / s), round(h / s)


def main():
    
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--now", action="store_true", help="skip the intro question")
    ap.add_argument("--screen", help="output name (kscreen-doctor -o), default: primary")
    ap.add_argument("--volume", type=float, default=1.0, help="0..1")
    ap.add_argument("--from", dest="start", type=float, default=0, help="start N seconds into the song")
    
    a = ap.parse_args()
    name, x, y, w, h = pick_screen(a.screen)
    cues = open(CUES).read()
    env = dict(os.environ, QT_QPA_PLATFORM="xcb", QT_QUICK_CONTROLS_STYLE="org.kde.desktop", QT_QUICK_BACKEND="software", QT_FORCE_STDERR_LOGGING="1")
    exe = runner()
    argv = ([exe, WINDOW_ICON] if exe else ["qml6", "-a", "widget", "--transparent"]) + [os.path.join(HERE, "show.qml"), "--", TRACK, cues, str(x), str(y), str(w), str(h), "0" if a.now else "1", str(LEAD), str(a.volume), str(a.start), name]
    restore_icons()                         
    saved = icons("save")
    
    if saved:
        with open(ICONS_BACKUP, "w") as f:
            f.write(saved)
    else:
        print("plasmashell not reachable: the desktop icons will stay where they are")
    def stop(*_):
        raise KeyboardInterrupt
    
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)
    
    print("\033[1;31mstarting bad orange..\033[0m  (Esc in any popup or Ctrl+C here to stop)")
    
    proc = subprocess.Popen(argv, env=env, start_new_session=True, stderr=subprocess.PIPE, text=True)
    pong = [threading.Event(), None]
    
    def stop_pong():
        pong[0].set()
        if pong[1]:
            pong[1].join()
    def play_pong(dur):
        end, t = time.monotonic() + dur, 0
        while not pong[0].is_set() and time.monotonic() < end:
            icons("pong", json.loads(saved), (x, y), t)
            t += 1
            pong[0].wait(PONG_FRAME)
    try:
        for line in proc.stderr:              # show.q asks icon moves on stderr
            if "NOTIFY " in line:
                title, text = json.loads(line.split("NOTIFY ", 1)[1])
                subprocess.Popen(["notify-send", "-a", "System Error Reporting", "-i", "dialog-error", "-t", "5500", "-e", title, text])
            
            elif "ICONS " in line:
                mode, dur = (line.split("ICONS ", 1)[1].split() + ["0"])[:2]
                stop_pong()
                if mode == "restore":
                    restore_icons()
                elif mode == "pong" and saved:
                    pong[:] = [threading.Event(), threading.Thread(target=play_pong, args=(float(dur),), daemon=True)]
                    pong[1].start()
                elif saved:
                    icons(mode, json.loads(saved))
            else:
                sys.stderr.write(line)
        return proc.wait()
    
    except KeyboardInterrupt:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait()
        return 0
    finally:
        stop_pong()
        restore_icons()

if __name__ == "__main__":
    sys.exit(main())
# the starter.