// parley-live.jsx — the live meeting screen (3 variants) + light interactivity
// Exports window.PkLiveMeeting

const I = () => window.PkIcon;

// ── Shared meeting data ───────────────────────────────────────────────
const PK_SPEAKERS = {
  you:    { name: "You",       chip: "var(--pk-accent)", ink: "#fff" },
  alana:  { name: "Alana P.",  chip: "#B14B3A", ink: "#fff" },
  marcus: { name: "Marcus K.", chip: "#5A6B7A", ink: "#fff" },
  priya:  { name: "Priya R.",  chip: "#8A7A3E", ink: "#fff" },
};

const PK_TRANSCRIPT = [
  { spk: "marcus", t: "12:21", text: "Last sprint we cleared the sync bug, so offline notes are stable now." },
  { spk: "alana",  t: "12:22", text: "Good — that unblocks the editor work we pushed out of Q2." },
  { spk: "priya",  t: "12:23", text: "I'd like the handwriting layer to ship in the same release. They read as one feature." },
  { spk: "you",    t: "12:24", text: "Agreed. Let's scope them together rather than splitting them up." },
  { spk: "marcus", t: "12:26", text: "Handwriting recognition is the unknown. The on-device model adds about three weeks." },
  { spk: "alana",  t: "12:27", text: "Three weeks is fine as long as it stays private. Nothing leaves the device." },
  { spk: "priya",  t: "12:28", text: "That's the whole promise — I'll hold the line on local-only." },
  { spk: "you",    t: "12:29", text: "Then the summary step has to run locally too. Let's confirm with the model team." },
  { spk: "marcus", t: "12:30", text: "I'll pull numbers on summarization latency by Thursday." },
];

function fmtClock(sec) {
  const m = Math.floor(sec / 60), s = sec % 60;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

// ── Hand-drawn doodle (the "sketch/diagram" Pencil stroke) ────────────
function PkDoodleArrow() {
  return (
    <span className="pk-doodle" style={{ display: "inline-block" }}>
      <svg width="118" height="40" viewBox="0 0 118 40" fill="none"
           stroke="var(--pk-hw-color)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M6 30c12-3 22 6 30-1 7-6 1-16 9-19 9-3 14 8 24 6" opacity="0.9" />
        <path d="M69 22c8 1 16-2 22-7" />
        <path d="M85 8c3 2 6 4 6 7-2 1-5 2-8 1" />
      </svg>
    </span>
  );
}
function PkUnderline({ w = 150 }) {
  return (
    <svg className="pk-hw" width={w} height="13" viewBox={`0 0 ${w} 13`} fill="none"
         stroke="var(--pk-hw-color)" strokeWidth="2.2" strokeLinecap="round" style={{ display: "block", marginTop: -2 }}>
      <path d={`M3 7c${w * 0.25} -5 ${w * 0.55} 8 ${w - 6} -2`} opacity="0.85" />
    </svg>
  );
}
function PkCircleScribble({ children }) {
  return (
    <span style={{ position: "relative", display: "inline-block", padding: "0 4px" }}>
      {children}
      <svg width="92" height="34" viewBox="0 0 92 34" fill="none" stroke="var(--pk-rec)"
           strokeWidth="1.8" strokeLinecap="round"
           style={{ position: "absolute", left: -8, top: -7, width: "calc(100% + 16px)", height: "calc(100% + 14px)", overflow: "visible" }}>
        <path d="M28 4C12 4 3 10 4 18c1 9 18 13 40 12 20-1 32-6 31-14C74 9 58 3 40 4" opacity="0.85" />
      </svg>
    </span>
  );
}

// ── Notes canvas (typed serif + handwriting + doodle + enrichment) ────
function PkNotesCanvas({ variant = "a" }) {
  const Ic = I();
  const sfx = "-" + variant;
  return (
    <div className="pk-notes">
      <div className="pk-notes-h">
        <span className="lbl">My Notes</span>
        <div className="pk-insert">
          <button className="pk-ins-btn pk-ins-primary" title="Insert"><span className="pk-ins-plus">{React.createElement(Ic.plus, { size: 15 })}</span> Insert</button>
          <button className="pk-iconbtn sm" title="Insert image">{React.createElement(Ic.image || Ic.folder, { size: 16 })}</button>
          <button className="pk-iconbtn sm" title="Attach file">{React.createElement(Ic.link, { size: 16 })}</button>
          <span className="saved">{React.createElement(Ic.cloudCheck, { size: 13 })} On device</span>
        </div>
      </div>

      <div className="pk-note-line h">Roadmap Review</div>
      <div className="pk-note-line" style={{ color: "var(--pk-ink-soft)", fontSize: 16, marginTop: -2, marginBottom: 8 }}>
        Q3 — what ships together
      </div>

      <div className="pk-hw-line" style={{ marginBottom: 2 }}>editor + handwriting = one release</div>
      <PkUnderline w={236} />

      <div style={{ height: 8 }} />

      <div className="pk-note-bullet"><span className="mk">—</span><span>On-device only. <span className="em">nothing leaves the iPad</span></span></div>
      <div className="pk-note-bullet"><span className="mk">—</span><span>Summary step must run locally too</span></div>

      {/* file attachments embedded in the note */}
      <div className="pk-filechips">
        <span className="pk-filechip"><span className="ic pdf">{React.createElement(Ic.list, { size: 13 })}</span>Q2-metrics.pdf<span className="mt">2.4 MB</span></span>
        <span className="pk-filechip"><span className="ic key">{React.createElement(Ic.folder, { size: 13 })}</span>Roadmap.key<span className="mt">14 slides</span></span>
      </div>

      {/* inline image embedded in the canvas (drag your own) */}
      <div className="pk-note-figure">
        <image-slot id={"pk-note-img" + sfx} shape="rounded" radius="8"
          placeholder="Drop a screenshot"
          style={{ display: "block", width: "100%", height: "84px" }}></image-slot>
        <div className="pk-fig-cap">Burndown — sprint 24</div>
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: 14, margin: "6px 0 0" }}>
        <PkDoodleArrow />
        <span className="pk-hw-aside" style={{ marginTop: -6, whiteSpace: "nowrap" }}>+3 wks for the model</span>
      </div>

      <div style={{ height: 4 }} />

      <div className="pk-note-line" style={{ fontWeight: 600, color: "var(--pk-ink)" }}>
        Decision:&nbsp;
        <span style={{ color: "var(--pk-accent-ink)" }}>ship together, local-first</span>
        <span className="pk-caret" />
      </div>

      {/* pinned photo with a handwritten caption */}
      <div className="pk-pin">
        <image-slot id={"pk-note-pin" + sfx} shape="rect"
          placeholder="Pin a photo"
          style={{ display: "block", width: "128px", height: "96px" }}></image-slot>
        <div className="pk-pin-cap">whiteboard from kickoff ↑</div>
        <span className="pk-pin-tack" />
      </div>
    </div>
  );
}

// ── Transcript feed ───────────────────────────────────────────────────
function PkTranscript({ variant, revealed }) {
  const lines = PK_TRANSCRIPT.slice(0, revealed);
  const curIdx = lines.length - 1;
  const Ic = I();
  return (
    <div className="pk-tx">
      <div className="pk-tx-h">
        <span className="ttl">{React.createElement(Ic.waveform, { size: 14 })} Transcript</span>
        <span className="pk-tx-live"><span className="d" /> Live</span>
      </div>
      <div className="pk-tx-feed">
        {lines.map((ln, i) => {
          const spk = PK_SPEAKERS[ln.spk];
          const cur = i === curIdx;
          const isLast = i === lines.length - 1;
          return (
            <div key={i} className={"pk-tx-line" + (cur ? " cur" : "") + (isLast ? " enter" : "")}>
              {variant === "c" && (
                <div className="pk-tx-node" />
              )}
              <div className="pk-tx-meta">
                {variant === "c" ? (
                  <span className="pk-spk-chip" style={{ background: spk.chip, color: spk.ink }}>
                    {spk.name.split(" ")[0][0]}
                  </span>
                ) : null}
                <span className="pk-tx-spk">{spk.name}</span>
                <span className="pk-tx-time">{ln.t}</span>
              </div>
              <div className="pk-tx-text">{ln.text}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ── Top bar ───────────────────────────────────────────────────────────
function PkTopBar({ variant, elapsed, recording, onToggle }) {
  const Ic = I();
  const StopGlyph = recording
    ? <span className="sq" />
    : React.createElement(Ic.circle, { size: 16, style: { color: "var(--pk-rec)" } });
  return (
    <div className="pk-top">
      <div className="pk-top-left">
        <button className="pk-iconbtn" title="Back to notes">{React.createElement(Ic.chevronLeft, { size: 18 })}</button>
        <div className="pk-titlewrap">
          <div className="pk-title" contentEditable suppressContentEditableWarning
               spellCheck={false} onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); e.currentTarget.blur(); } }}>
            Roadmap Review — Q3
          </div>
          <div className="pk-sub">
            <span>Thu, Jun 5</span><span className="dot" /><span>4 people</span><span className="dot" /><span>Product</span>
          </div>
        </div>
      </div>

      {variant === "c" && (
        <div className="pk-top-center">
          <div className="pk-timer">{fmtClock(elapsed)}</div>
          <div className="cap"><span className="pk-rec-dot" style={{ width: 7, height: 7 }} /> Recording</div>
        </div>
      )}

      <div className="pk-status">
        {variant !== "c" && (
          <div className="pk-rec">
            <span className="pk-rec-dot" />
            <span className="pk-rec-label">Rec</span>
            <span className="pk-timer">{fmtClock(elapsed)}</span>
          </div>
        )}
        <button className="pk-stop" onClick={onToggle} title={recording ? "Stop recording" : "Resume recording"}>
          {StopGlyph}
        </button>
      </div>
    </div>
  );
}

// ── Bottom bar ────────────────────────────────────────────────────────
function PkBottomBar() {
  const Ic = I();
  return (
    <div className="pk-bottom">
      <div className="hint">{React.createElement(Ic.pencil, { size: 14 })} Type, or write with Apple&nbsp;Pencil</div>
      <div className="pk-actions">
        <button className="pk-btn pk-btn-ghost">{React.createElement(Ic.flag, { size: 16 })} Flag action item</button>
        <button className="pk-btn pk-btn-summary">
          {React.createElement(Ic.sparkles, { size: 16 })} Summarize
          <span className="when">when you end</span>
        </button>
      </div>
    </div>
  );
}

// ── The screen ────────────────────────────────────────────────────────
function PkLiveMeeting({ variant = "a" }) {
  const [elapsed, setElapsed] = React.useState(12 * 60 + 21);
  const [recording, setRecording] = React.useState(true);
  const [revealed, setRevealed] = React.useState(7);

  React.useEffect(() => {
    if (!recording) return;
    const id = setInterval(() => setElapsed((e) => e + 1), 1000);
    return () => clearInterval(id);
  }, [recording]);

  React.useEffect(() => {
    if (!recording) return;
    const id = setInterval(() => {
      setRevealed((r) => (r < PK_TRANSCRIPT.length ? r + 1 : r));
    }, 5200);
    return () => clearInterval(id);
  }, [recording]);

  return (
    <div className={"pk-frame v-" + variant}>
      <PkTopBar variant={variant} elapsed={elapsed} recording={recording}
                onToggle={() => setRecording((r) => !r)} />
      <div className="pk-main">
        <PkNotesCanvas variant={variant} />
        <PkTranscript variant={variant} revealed={revealed} />
      </div>
      <PkBottomBar />
    </div>
  );
}

window.PkLiveMeeting = PkLiveMeeting;
