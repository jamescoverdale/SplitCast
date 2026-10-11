"""Draws the sample-data app screens for the Splitcast site (compare, goal, widgets SVGs).

Usage: python3 tools/make_splitcast_screens.py site/assets/screens
"""
import math, sys
out = sys.argv[1]
FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
ORANGE, BLUE, GREEN, GREY, INK = "#ff8a1f", "#2f7bf6", "#30b45a", "#8e8e93", "#111114"

def phone(body, bg="#f2f2f7", status_dark=True):
    sc = INK if status_dark else "#fff"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 390 800" width="390" height="800" font-family="{FONT}">
<defs><clipPath id="s"><rect x="10" y="10" width="370" height="780" rx="40"/></clipPath></defs>
<rect width="390" height="800" rx="50" fill="#1b1c20"/>
<g clip-path="url(#s)"><rect x="10" y="10" width="370" height="780" fill="{bg}"/>
{body}
<text x="44" y="40" font-size="15" font-weight="600" fill="{sc}">9:41</text>
<rect x="150" y="22" width="90" height="26" rx="13" fill="#000"/>
<rect x="318" y="29" width="26" height="12" rx="3.5" fill="none" stroke="{sc}" stroke-opacity=".5"/><rect x="320" y="31" width="19" height="8" rx="2" fill="{sc}"/>
</g></svg>
'''

def tabbar(sel):
    items = [("Compare", "⇄"), ("Goal", "◎"), ("Results", "⚑")]
    s = '<rect x="62" y="712" width="266" height="60" rx="30" fill="#fff" stroke="#e3e3e8"/>'
    for i, (name, glyph) in enumerate(items):
        cx = 108 + i * 87
        col = BLUE if name == sel else INK
        if name == sel:
            s += f'<rect x="{cx-40}" y="717" width="80" height="50" rx="25" fill="#eaf1fe"/>'
        s += f'<text x="{cx}" y="743" font-size="20" text-anchor="middle" fill="{col}">{glyph}</text>'
        s += f'<text x="{cx}" y="761" font-size="11" font-weight="600" text-anchor="middle" fill="{col}">{name}</text>'
    return s

def card(x, y, w, h):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="22" fill="#fff"/>'

def numberline(y, lo, hi, marks, rng=None):
    # marks: (seconds, label, colour, above, anchor)
    x = lambda t: 46 + (t - lo) / (hi - lo) * 298
    s = f'<line x1="46" y1="{y}" x2="344" y2="{y}" stroke="#d6d6db" stroke-width="4" stroke-linecap="round"/>'
    if rng:
        s += f'<rect x="{x(rng[0]):.0f}" y="{y-5}" width="{x(rng[1])-x(rng[0]):.0f}" height="10" rx="5" fill="#cfe0fb"/>'
    for t, label, col, above, anchor in marks:
        s += f'<circle cx="{x(t):.1f}" cy="{y}" r="8" fill="{col}" stroke="#fff" stroke-width="2"/>'
        dx = {"end": 4, "start": -4, "middle": 0}[anchor]
        ly = y - 18 if above else y + 28
        s += f'<text x="{x(t)+dx:.1f}" y="{ly}" font-size="13" font-weight="600" text-anchor="{anchor}" fill="{col}">{label}</text>'
    return s, x

def clock(sec):
    return f"{int(sec // 60)}:{int(sec % 60):02d}"

# ---------- Compare ----------
b = f'<text x="195" y="80" font-size="17" font-weight="600" text-anchor="middle" fill="{INK}">Then vs now</text>'
b += f'<circle cx="345" cy="75" r="18" fill="#fff" stroke="#e3e3e8"/><text x="345" y="81" font-size="17" text-anchor="middle" fill="{INK}">⇅</text>'
b += card(26, 100, 338, 296)
b += f'<text x="46" y="134" font-size="15" fill="#6b6b70">That 5k today</text>'
b += f'<rect x="236" y="117" width="110" height="25" rx="12.5" fill="#e3f6e8"/><text x="291" y="134" font-size="13" font-weight="600" text-anchor="middle" fill="#1f8f40">▼ 0:28 faster</text>'
b += f'<text x="42" y="206" font-size="66" font-weight="800" letter-spacing="-1" fill="{INK}">20:42</text>'
b += f'<text x="46" y="234" font-size="13" fill="#6b6b70">6:40/mi · likely between 20:05 and 21:20</text>'
lo, hi = 19*60+50, 21*60+30
nl, _ = numberline(290, lo, hi, [(20*60+42, "Now 20:42", BLUE, True, "end"), (21*60+10, "Then 21:10", ORANGE, True, "start")], (20*60+5, 21*60+20))
b += nl + f'<text x="242" y="315" font-size="12" font-weight="600" text-anchor="middle" fill="#6b6b70">0:28</text>'
b += '<line x1="46" y1="330" x2="344" y2="330" stroke="#ececf0"/>'
for cx, big, small, lab, col in [(100, "82", "/100", "Fitness score", INK), (195, "+5%", "", "vs then", "#1f8f40"), (290, "11", "/12", "Data used ›", INK)]:
    b += f'<text x="{cx}" y="364" font-size="24" font-weight="700" text-anchor="middle" fill="{col}">{big}<tspan font-size="12" font-weight="400" fill="#8e8e93">{small}</tspan></text>'
    b += f'<text x="{cx}" y="384" font-size="12" text-anchor="middle" fill="#6b6b70">{lab}</text>'
b += f'<text x="40" y="430" font-size="20" font-weight="700" fill="#3a3a3c">Steady runs</text><text x="350" y="430" font-size="11" text-anchor="end" fill="{GREY}">heart rate at each pace</text>'
b += card(26, 444, 338, 254)
px = lambda m, s: 46 + ((m*60+s) - 390) / 240 * 270
py = lambda bpm: 635 - (bpm - 125) * 4.25
for bpm in (130, 140, 150, 160):
    b += f'<line x1="46" y1="{py(bpm)}" x2="316" y2="{py(bpm)}" stroke="#ececf0"/><text x="322" y="{py(bpm)+4}" font-size="10" fill="{GREY}">{bpm}</text>'
for m in (7, 8, 9, 10):
    b += f'<text x="{px(m,0):.0f}" y="652" font-size="10" text-anchor="middle" fill="{GREY}">{m}:00</text>'
then = [(7,20,158),(7,45,153),(8,5,150),(8,15,148),(8,30,146),(8,40,145),(8,50,143),(9,0,144),(9,10,141),(9,20,140),(9,35,138),(9,50,137),(10,5,134),(8,25,151),(9,5,146)]
now = [(7,10,152),(7,30,149),(7,55,145),(8,10,143),(8,20,140),(8,35,139),(8,50,137),(9,0,138),(9,15,135),(9,30,133),(9,45,131),(10,0,130),(8,45,141)]
for pts, col in ((then, ORANGE), (now, BLUE)):
    for m, s, h in pts:
        b += f'<circle cx="{px(m,s):.1f}" cy="{py(h):.1f}" r="5" fill="{col}" fill-opacity=".9"/>'
b += f'<circle cx="52" cy="666" r="4" fill="{ORANGE}"/><text x="60" y="670" font-size="11" fill="#6b6b70">6 weeks before then</text>'
b += f'<circle cx="182" cy="666" r="4" fill="{BLUE}"/><text x="190" y="670" font-size="11" fill="#6b6b70">Last 6 weeks</text>'
b += f'<text x="46" y="688" font-size="12" fill="{INK}">At the same pace, your heart works about 6 bpm less.</text>'
b += tabbar("Compare")
open(f"{out}/compare.svg", "w").write(phone(b))

# ---------- Goal ----------
b = f'<text x="195" y="80" font-size="17" font-weight="600" text-anchor="middle" fill="{INK}">Goal</text>'
b += '<rect x="26" y="98" width="338" height="30" rx="9" fill="#e4e4ea"/><rect x="28" y="100" width="83" height="26" rx="7" fill="#fff"/>'
for i, d in enumerate(["5k", "10k", "Half", "Marathon"]):
    b += f'<text x="{69 + i*84}" y="118" font-size="13" font-weight="{600 if i == 0 else 400}" text-anchor="middle" fill="{INK}">{d}</text>'
b += card(26, 140, 338, 230)
b += f'<text x="46" y="172" font-size="15" fill="#6b6b70">Predicted 5k today</text>'
b += f'<rect x="248" y="155" width="98" height="25" rx="12.5" fill="#e4f6ea"/><text x="297" y="172" font-size="13" font-weight="600" text-anchor="middle" fill="#1f8f40">Goal 19:59</text>'
b += f'<text x="42" y="242" font-size="66" font-weight="800" letter-spacing="-1" fill="{INK}">20:42</text>'
b += f'<text x="46" y="268" font-size="13" fill="#6b6b70">6:40/mi · 0:43 to go, 3.5% faster</text>'
lo, hi = 19*60+40, 21*60
nl, _ = numberline(320, lo, hi, [(19*60+59, "Goal 19:59", GREEN, True, "middle"), (20*60+42, "Now 20:42", BLUE, True, "middle"), (20*60+18, "Best 20:18", "#7d7d85", False, "middle")])
b += nl
b += f'<text x="40" y="408" font-size="20" font-weight="700" fill="#3a3a3c">Over time</text>'
b += '<rect x="248" y="392" width="116" height="24" rx="8" fill="#e4e4ea"/><rect x="250" y="394" width="38" height="20" rx="6" fill="#fff"/>'
for i, t in enumerate(["1Y", "2Y", "5Y"]):
    b += f'<text x="{269 + i*38}" y="408" font-size="11" font-weight="600" text-anchor="middle" fill="{INK}">{t}</text>'
b += card(26, 424, 338, 196)
gy = lambda sec: 448 + (sec - (19*60+45)) / 120 * 140
gx = lambda w: 50 + w / 52 * 262
for sec in (20*60, 20*60+30, 21*60, 21*60+30):
    b += f'<line x1="50" y1="{gy(sec):.1f}" x2="312" y2="{gy(sec):.1f}" stroke="#ececf0"/><text x="318" y="{gy(sec)+4:.1f}" font-size="10" fill="{GREY}">{clock(sec)}</text>'
pts = []
for w in range(53):
    sec = 21*60+35 - 53 * w / 52 + 9 * math.sin(w / 3.1) + 5 * math.sin(w / 1.3)
    if 22 <= w <= 30:
        sec += 12 * math.sin((w - 22) / 8 * math.pi)
    pts.append(f"{gx(w):.1f},{gy(sec):.1f}")
b += f'<rect x="50" y="{gy(19*60+59)-1:.1f}" width="262" height="2" fill="{GREEN}" opacity=".7"/><text x="54" y="{gy(19*60+59)-6:.1f}" font-size="10" font-weight="600" fill="{GREEN}">Goal</text>'
b += f'<polyline points="{" ".join(pts)}" fill="none" stroke="{BLUE}" stroke-width="2.5" stroke-linejoin="round"/>'
for w, sec in ((9, 21*60+30), (24, 21*60+3), (38, 20*60+44), (46, 20*60+18)):
    b += f'<circle cx="{gx(w):.1f}" cy="{gy(sec):.1f}" r="5.5" fill="{ORANGE}" stroke="#fff" stroke-width="2"/>'
b += f'<circle cx="56" cy="606" r="4" fill="{BLUE}"/><text x="64" y="610" font-size="11" fill="#6b6b70">Predicted</text><circle cx="132" cy="606" r="4" fill="{ORANGE}"/><text x="140" y="610" font-size="11" fill="#6b6b70">Your races</text>'
b += card(26, 632, 338, 66)
b += f'<text x="46" y="658" font-size="15" font-weight="600" fill="{INK}">How good is this?</text>'
b += f'<text x="46" y="680" font-size="12" fill="#6b6b70">On your last 6 races it was off by 3% on average.</text>'
b += tabbar("Goal")
open(f"{out}/goal.svg", "w").write(phone(b))

# ---------- Widgets ----------
spark = lambda x0, y0, w, h: " ".join(f"{x0 + i / 25 * w:.1f},{y0 + h * (0.15 + 0.7 * (1 - i/25) + 0.12 * math.sin(i / 1.7)):.1f}" for i in range(26))
b = '<defs><linearGradient id="wp" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1fc2da"/><stop offset=".55" stop-color="#2b86f0"/><stop offset="1" stop-color="#3a4fe0"/></linearGradient></defs>'
b += '<rect x="10" y="10" width="370" height="780" fill="url(#wp)"/>'
b += '<text x="195" y="150" font-size="72" font-weight="300" text-anchor="middle" fill="#fff" opacity=".95">9:41</text>'
b += '<text x="195" y="70" font-size="16" font-weight="600" text-anchor="middle" fill="#fff" opacity=".9">Tuesday 7 October</text>'
b += '<rect x="80" y="170" width="230" height="58" rx="16" fill="#fff" fill-opacity=".22"/>'
b += '<text x="98" y="194" font-size="12" font-weight="700" fill="#fff">5K · SPLITCAST</text><text x="98" y="216" font-size="17" font-weight="700" fill="#fff">20:42 <tspan font-size="12" font-weight="500">likely 20:05–21:20</tspan></text>'
b += card(26, 250, 158, 158)
b += f'<text x="42" y="278" font-size="12" font-weight="700" fill="{BLUE}">5K</text><text x="42" y="318" font-size="34" font-weight="800" fill="{INK}">20:42</text>'
b += f'<text x="42" y="338" font-size="11" font-weight="600" fill="#1f8f40">▼ 0:28 in 6 weeks</text>'
b += f'<polyline points="{spark(42, 352, 126, 40)}" fill="none" stroke="{BLUE}" stroke-width="2.5" stroke-linejoin="round"/>'
b += card(206, 250, 158, 158)
b += f'<text x="222" y="278" font-size="12" font-weight="700" fill="{GREEN}">GOAL 19:59</text><text x="222" y="314" font-size="15" font-weight="700" fill="{INK}">Within reach</text>'
b += f'<text x="222" y="334" font-size="11" fill="#6b6b70">Predicted 20:42</text><text x="222" y="350" font-size="11" fill="#6b6b70">0:43 to go</text>'
b += f'<rect x="222" y="370" width="126" height="8" rx="4" fill="#e4f6ea"/><rect x="222" y="370" width="112" height="8" rx="4" fill="{GREEN}"/>'
b += card(26, 430, 338, 158)
b += f'<text x="44" y="460" font-size="12" font-weight="700" fill="{BLUE}">HALF MARATHON</text><text x="44" y="502" font-size="36" font-weight="800" fill="{INK}">1:34:10</text>'
b += f'<text x="44" y="526" font-size="12" fill="#6b6b70">7:11/mi · 1:31:40–1:37:05</text>'
b += f'<polyline points="{spark(250, 474, 96, 50)}" fill="none" stroke="{BLUE}" stroke-width="2.5" stroke-linejoin="round"/>'
b += f'<line x1="250" y1="476" x2="346" y2="476" stroke="{GREEN}" stroke-dasharray="4 4"/>'
b += f'<text x="44" y="566" font-size="11" fill="{GREY}">Updated after this morning\'s run</text>'
for i in range(4):
    b += f'<rect x="{38 + i*84}" y="616" width="62" height="62" rx="15" fill="#fff" fill-opacity=".25"/>'
b += '<rect x="34" y="712" width="322" height="70" rx="28" fill="#fff" fill-opacity=".22"/>'
open(f"{out}/widgets.svg", "w").write(phone(b, status_dark=False))
