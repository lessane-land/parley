// parley-app.jsx — root: mood-aware Tweaks → CSS vars, screens on a design canvas

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "mood": "paper",
  "accent": "#3E5C50",
  "font": "Newsreader",
  "warmth": 38,
  "highlight": "#D8F000",
  "grid": true,
  "density": "regular",
  "handwriting": true
}/*EDITMODE-END*/;

// ── color helpers ─────────────────────────────────────────────────────
function pkHex(h) {
  const x = h.replace("#", "");
  const n = x.length === 3 ? x.replace(/./g, (c) => c + c) : x;
  return [parseInt(n.slice(0, 2), 16), parseInt(n.slice(2, 4), 16), parseInt(n.slice(4, 6), 16)];
}
function pkRgb(r) { return "#" + r.map((v) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, "0")).join(""); }
function pkMix(a, b, t) { const A = pkHex(a), B = pkHex(b); return pkRgb([0, 1, 2].map((i) => A[i] + (B[i] - A[i]) * t)); }
function pkRgba(h, a) { const [r, g, b] = pkHex(h); return `rgba(${r},${g},${b},${a})`; }

// ── font stacks ───────────────────────────────────────────────────────
const PK_FONT = {
  "Newsreader":     '"Newsreader", Georgia, serif',
  "Fraunces":       '"Fraunces", Georgia, serif',
  "Source Serif 4": '"Source Serif 4", Georgia, serif',
  "Spectral":       '"Spectral", Georgia, serif',
  "Space Grotesk":  '"Space Grotesk", system-ui, sans-serif',
  "IBM Plex Mono":  '"IBM Plex Mono", ui-monospace, monospace',
  "Archivo":        '"Archivo", system-ui, sans-serif',
  "Inter":          '"Inter", system-ui, sans-serif',
  "Archivo Black":  '"Archivo Black", "Archivo", sans-serif',
};

// ── mood configs (each carries its own accent/​font/​extra options) ──────
const PK_MOODS = {
  paper: {
    label: "Paper",
    blurb: "Warm digital paper",
    accents: ["#3E5C50", "#8B3A2F", "#C75B39", "#27406B"],
    accent: "#3E5C50",
    font: { label: "Note serif", vars: ["--pk-serif"], options: ["Newsreader", "Fraunces", "Source Serif 4", "Spectral"], default: "Newsreader" },
    warmth: true,
  },
  terminal: {
    label: "Terminal",
    blurb: "Engineered, dark, dense",
    accents: ["#FF9F1C", "#36E08B", "#54C7FF", "#FF5C4D"],
    accent: "#FF9F1C",
    font: { label: "Interface face", vars: ["--pk-serif", "--pk-sans"], options: ["Space Grotesk", "IBM Plex Mono"], default: "Space Grotesk" },
    grid: true,
  },
  swiss: {
    label: "Swiss",
    blurb: "Stark, gridded, bold",
    accents: ["#E2231A", "#0A5FFF", "#111111", "#FF6A00"],
    accent: "#E2231A",
    font: { label: "Grotesque", vars: ["--pk-serif", "--pk-sans", "--pk-tx-font"], options: ["Archivo", "Inter"], default: "Archivo" },
  },
  neubrutalist: {
    label: "Neubrutalist",
    blurb: "Bold, bordered, electric",
    accents: ["#2B4BF2", "#FF4FA3", "#FF6A1A", "#16A34A"],
    accent: "#2B4BF2",
    highlights: ["#D8F000", "#FFE600", "#00E5FF", "#FF4FA3"],
    highlight: "#D8F000",
    font: { label: "Display face", vars: ["--pk-display"], options: ["Archivo Black", "Space Grotesk", "Archivo"], default: "Archivo Black" },
  },
};
const PK_MOOD_IDS = Object.keys(PK_MOODS);

// Inline props this controller manages — cleared before each apply so a
// value set under one mood never leaks into the next.
const PK_MANAGED = [
  "--pk-paper", "--pk-paper-rec", "--pk-paper-sink", "--pk-edge",
  "--pk-accent", "--pk-accent-ink", "--pk-accent-tint", "--pk-accent-line",
  "--pk-rec", "--pk-hw-color", "--pk-serif", "--pk-sans", "--pk-tx-font", "--pk-display",
];

function applyAccent(B, mood, accent, highlight, paper) {
  const S = (k, v) => B.setProperty(k, v);
  S("--pk-accent", accent);
  S("--pk-accent-line", pkRgba(accent, 0.34));
  S("--pk-rec", accent);
  if (mood === "terminal") {
    S("--pk-accent-ink", pkMix(accent, "#FFFFFF", 0.22));
    S("--pk-accent-tint", pkMix("#141A24", accent, 0.16));
    S("--pk-hw-color", pkMix(accent, "#FFFFFF", 0.12));
  } else if (mood === "neubrutalist") {
    S("--pk-accent-ink", pkMix(accent, "#000000", 0.18));
    S("--pk-accent-tint", highlight);            // the single loud highlight
    S("--pk-accent-line", "#1A1A1A");            // borders stay black
    S("--pk-hw-color", accent);
  } else if (mood === "swiss") {
    S("--pk-accent-ink", pkMix(accent, "#000000", 0.16));
    S("--pk-accent-tint", pkMix("#FFFFFF", accent, 0.10));
    S("--pk-hw-color", accent);
  } else { // paper
    const base = paper || "#F4EFE6";
    S("--pk-accent-ink", pkMix(accent, "#1A1812", 0.28));
    S("--pk-accent-tint", pkMix(base, accent, 0.13));
    S("--pk-hw-color", pkMix(accent, "#1A1812", 0.18));
  }
}

function PkRoot() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const cfg = PK_MOODS[t.mood] || PK_MOODS.paper;

  React.useEffect(() => {
    const B = document.body.style;
    const mood = PK_MOODS[t.mood] ? t.mood : "paper";
    const m = PK_MOODS[mood];

    // mood class drives the base re-skin
    PK_MOOD_IDS.forEach((id) => document.body.classList.remove("mood-" + id));
    document.body.classList.add("mood-" + mood);

    // reset managed inline overrides so nothing leaks across moods
    PK_MANAGED.forEach((p) => B.removeProperty(p));

    // fonts
    const stack = PK_FONT[t.font] || "";
    if (stack) m.font.vars.forEach((v) => B.setProperty(v, stack));

    // paper warmth (paper mood only): cool off-white → cream
    let paper = null;
    if (m.warmth) {
      paper = pkMix("#F8F4EC", "#F1E3C4", t.warmth / 100);
      B.setProperty("--pk-paper", paper);
      B.setProperty("--pk-paper-rec", pkMix(paper, "#FFFFFF", 0.42));
      B.setProperty("--pk-paper-sink", pkMix(paper, "#5A5036", 0.07));
      B.setProperty("--pk-edge", pkMix(paper, "#5A5036", 0.16));
    }

    // accent family (mood-aware derivation)
    applyAccent(B, mood, t.accent, t.highlight, paper);

    // extras
    document.body.classList.toggle("grid-off", !t.grid);
    document.body.classList.remove("density-compact", "density-regular", "density-comfy");
    document.body.classList.add("density-" + t.density);
    document.body.classList.toggle("hide-hw", !t.handwriting);
  }, [t]);

  // switching mood resets its dependent options to that mood's defaults
  const pickMood = (label) => {
    const id = PK_MOOD_IDS.find((k) => PK_MOODS[k].label === label) || "paper";
    const m = PK_MOODS[id];
    const next = { mood: id, accent: m.accent, font: m.font.default };
    if (m.highlight) next.highlight = m.highlight;
    setTweak(next);
  };

  return (
    <React.Fragment>
      <DesignCanvas>
        <DCSection id="live" title="Live meeting" subtitle="Recording, mid-meeting — three directions for the notes / transcript split. Title is editable · timer ticks · transcript streams in.">
          <DCArtboard id="a" label="A · Classic split" width={1194} height={834}><PkLiveMeeting variant="a" /></DCArtboard>
          <DCArtboard id="b" label="B · Two documents" width={1194} height={834}><PkLiveMeeting variant="b" /></DCArtboard>
          <DCArtboard id="c" label="C · Editorial focus" width={1194} height={834}><PkLiveMeeting variant="c" /></DCArtboard>
        </DCSection>

        <DCSection id="companions" title="Companion screens" subtitle="Where the live screen lives — before and after the meeting. Home now carries the on-device “Ask Parley” chat; Settings slides in from the right.">
          <DCArtboard id="home" label="Home · All notes + Ask Parley" width={1194} height={834}><PkHome /></DCArtboard>
          <DCArtboard id="summary" label="Post-meeting summary" width={1194} height={834}><PkSummary /></DCArtboard>
          <DCArtboard id="settings" label="Settings · slide-over" width={1194} height={834}><PkSettingsScene /></DCArtboard>
        </DCSection>

        <DCSection id="identity" title="App icon" subtitle="Motif: a “P” whose bowl opens like a speech turn. The icon restyles per mood — and recolors with the accent you pick.">
          <DCArtboard id="icon" label="App icon · iPhone · iPad · Mac" width={1194} height={834}><PkIconShowcase /></DCArtboard>
        </DCSection>
      </DesignCanvas>

      <TweaksPanel title="Tweaks">
        <TweakSection label="Mood" />
        <TweakSelect label="Visual mood" value={cfg.label}
          options={PK_MOOD_IDS.map((id) => PK_MOODS[id].label)}
          onChange={pickMood} />

        <TweakSection label={cfg.label + " — " + cfg.blurb} />
        <TweakColor label="Accent" value={t.accent} options={cfg.accents}
          onChange={(v) => setTweak("accent", v)} />
        {cfg.highlights && (
          <TweakColor label="Highlight" value={t.highlight} options={cfg.highlights}
            onChange={(v) => setTweak("highlight", v)} />
        )}
        {cfg.warmth && (
          <TweakSlider label="Paper warmth" value={t.warmth} min={0} max={100} unit=""
            onChange={(v) => setTweak("warmth", v)} />
        )}
        <TweakSelect label={cfg.font.label} value={t.font} options={cfg.font.options}
          onChange={(v) => setTweak("font", v)} />
        {cfg.grid && (
          <TweakToggle label="Hairline grid" value={t.grid}
            onChange={(v) => setTweak("grid", v)} />
        )}

        <TweakSection label="Live screen" />
        <TweakRadio label="Transcript density" value={t.density}
          options={["compact", "regular", "comfy"]}
          onChange={(v) => setTweak("density", v)} />
        <TweakToggle label="Handwriting strokes" value={t.handwriting}
          onChange={(v) => setTweak("handwriting", v)} />
      </TweaksPanel>
    </React.Fragment>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<PkRoot />);
