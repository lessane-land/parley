// parley-companions.jsx — home / notes list + post-meeting summary
// Exports window.PkHome, window.PkSummary

const CI = () => window.PkIcon;

const PK_PEOPLE = {
  you:    { initials: "Yo", chip: "var(--pk-accent)" },
  alana:  { initials: "AP", chip: "#B14B3A" },
  marcus: { initials: "MK", chip: "#5A6B7A" },
  priya:  { initials: "PR", chip: "#8A7A3E" },
  dana:   { initials: "DL", chip: "#7A6A55" },
};
function Av({ who, size = 21, cls = "av" }) {
  const p = PK_PEOPLE[who];
  return <div className={cls} style={{ background: p.chip, width: size, height: size }}>{p.initials}</div>;
}

// ════════════════════ SHARED SIDEBAR ════════════════════
function PkSidebar({ active = "notes" }) {
  const Ic = CI();
  const nav = [
    { id: "notes", icon: "list", label: "All notes", ct: "38" },
    { id: "calendar", icon: "calendar", label: "Calendar" },
    { id: "recents", icon: "clock", label: "Recents" },
    { id: "ask", icon: "sparkles", label: "Ask Parley" },
    { id: "actions", icon: "flag", label: "Action items", ct: "7" },
    { id: "archive", icon: "folder", label: "Archive" },
  ];
  return (
    <aside className="pk-side">
      <div className="pk-brand">
        <PkAppIcon size={32} />
        <div className="wm">Parley</div>
      </div>
      <div className="pk-searchbar">{React.createElement(Ic.search, { size: 15 })}<span>Search notes &amp; transcripts</span></div>
      <nav className="pk-nav">
        {nav.map((n) => (
          <div key={n.id} className={"pk-nav-item" + (n.id === active ? " on" : "")}>
            {React.createElement(Ic[n.icon], { size: 17 })}
            <span>{n.label}</span>
            {n.ct && <span className="ct">{n.ct}</span>}
          </div>
        ))}
      </nav>
      <div className="pk-nav-h">Spaces</div>
      <div className="pk-tag"><span className="sw" style={{ background: "var(--pk-accent)" }} />Product</div>
      <div className="pk-tag"><span className="sw" style={{ background: "#B14B3A" }} />1:1s</div>
      <div className="pk-tag"><span className="sw" style={{ background: "#5A6B7A" }} />Research</div>
      <div className="pk-side-foot">
        <button className="pk-set-link">{React.createElement(Ic.gear, { size: 16 })} Settings</button>
        <button className="pk-record-cta"><span className="rd" /> New recording</button>
      </div>
    </aside>
  );
}

// ════════════════════ HOME / NOTES LIST ════════════════════
function PkHome({ compact }) {
  const Ic = CI();
  return (
    <div className={"pk-home" + (compact ? "" : " has-ask")}>
      <PkSidebar active="notes" />

      <main className="pk-home-main">
        <div className="pk-home-head">
          <div>
            <h1>All notes</h1>
            <div className="meta">38 notes · last edited just now · everything on this iPad</div>
          </div>
          <div className="pk-seg">
            <button className="on">Recent</button>
            <button>By space</button>
            <button>Flagged</button>
          </div>
        </div>

        <div className="pk-daygroup">Today</div>
        <div className="pk-grid">
          <article className="pk-card feature">
            <div className="ct-date"><span className="lv"><span className="pk-rec-dot" /> Recording now</span> · 12:21 elapsed</div>
            <h3>Roadmap Review — Q3</h3>
            <p className="snip">editor + handwriting = one release · on-device only, nothing leaves the iPad · summary step must run locally too · decision: ship together, local-first…</p>
            <div className="foot">
              <div className="pk-avatars"><Av who="you" /><Av who="alana" /><Av who="marcus" /><Av who="priya" /></div>
              <div className="pk-chiprow">
                <span className="pk-meta-chip acc">{React.createElement(Ic.pencil, { size: 13 })} Handwriting</span>
                <span className="pk-meta-chip">{React.createElement(Ic.flag, { size: 13 })} 2</span>
              </div>
            </div>
          </article>

          <article className="pk-card">
            <span className="hw-flag">{React.createElement(Ic.pencil, { size: 15 })}</span>
            <div className="ct-date">9:30 AM · 24 min</div>
            <h3>Design crit — onboarding</h3>
            <p className="snip">First-run should explain local-first in one sentence. Priya to redraw the empty state by Friday.</p>
            <div className="foot">
              <div className="pk-avatars"><Av who="you" /><Av who="priya" /></div>
              <div className="pk-chiprow"><span className="pk-meta-chip">{React.createElement(Ic.flag, { size: 13 })} 1</span></div>
            </div>
          </article>
        </div>

        <div className="pk-daygroup" style={{ marginTop: 22 }}>Yesterday</div>
        <div className="pk-grid">
          <article className="pk-card">
            <div className="ct-date">4:10 PM · 18 min</div>
            <h3>1:1 — Marcus</h3>
            <p className="snip">On-device model latency is the open risk. Numbers by Thursday before we commit Q3 scope.</p>
            <div className="foot"><div className="pk-avatars"><Av who="you" /><Av who="marcus" /></div></div>
          </article>
          <article className="pk-card">
            <span className="hw-flag">{React.createElement(Ic.pencil, { size: 15 })}</span>
            <div className="ct-date">11:00 AM · 41 min</div>
            <h3>User interviews — wrap-up</h3>
            <p className="snip">People want notes that feel like paper, not another database. Privacy came up unprompted in 4 of 6 sessions.</p>
            <div className="foot">
              <div className="pk-avatars"><Av who="you" /><Av who="priya" /><Av who="dana" /></div>
              <div className="pk-chiprow"><span className="pk-meta-chip">{React.createElement(Ic.flag, { size: 13 })} 3</span></div>
            </div>
          </article>
          <article className="pk-card">
            <div className="ct-date">9:00 AM · 12 min</div>
            <h3>Standup</h3>
            <p className="snip">Sync bug closed. Editor work unblocked for the week.</p>
            <div className="foot"><div className="pk-avatars"><Av who="you" /><Av who="marcus" /><Av who="alana" /></div></div>
          </article>
        </div>
      </main>

      {!compact && (
        <aside className="pk-ask">
          <div className="pk-ask-head">
            <div className="pk-ask-title">{React.createElement(Ic.sparkles, { size: 16 })} Ask Parley</div>
            <div className="pk-ask-sub">Across all your notes · on device</div>
          </div>

          <div className="pk-ask-feed">
            <div className="pk-msg user"><div className="bub">What did we decide about shipping handwriting?</div></div>
            <div className="pk-msg bot">
              <div className="bub">
                You agreed to ship the editor and the handwriting layer <b>together in one Q3 release</b>, and to keep the whole pipeline — including summaries — <b>on device</b>.
                <div className="pk-cites">
                  <span className="pk-cite">{React.createElement(Ic.waveform, { size: 11 })} Roadmap Review · 12:24</span>
                  <span className="pk-cite">{React.createElement(Ic.pencil, { size: 11 })} My notes · Decision</span>
                </div>
              </div>
            </div>
            <div className="pk-msg user"><div className="bub">Who owns the latency check, and by when?</div></div>
            <div className="pk-msg bot">
              <div className="bub">
                <b>Marcus</b> is pulling summarization latency numbers, due <b>Thursday</b> — before Q3 scope is locked.
                <div className="pk-cites">
                  <span className="pk-cite">{React.createElement(Ic.waveform, { size: 11 })} 1:1 — Marcus · 4:10</span>
                </div>
              </div>
            </div>
          </div>

          <div className="pk-ask-prompts">
            <span className="pk-chip">Open action items</span>
            <span className="pk-chip">What's still undecided?</span>
            <span className="pk-chip">Summarize this week</span>
          </div>

          <div className="pk-ask-input">
            <input placeholder="Ask about your notes…" readOnly />
            <button className="pk-ask-send">{React.createElement(Ic.send, { size: 16 })}</button>
          </div>
          <div className="pk-ask-foot">{React.createElement(Ic.bolt, { size: 12 })} Answers stay on this iPad</div>
        </aside>
      )}
    </div>
  );
}

// ════════════════════ POST-MEETING SUMMARY ════════════════════
function PkSummary() {
  const Ic = CI();
  return (
    <div className="pk-sum">
      <div className="pk-sum-top">
        <button className="pk-iconbtn" title="Back">{React.createElement(Ic.chevronLeft, { size: 18 })}</button>
        <div className="pk-titlewrap">
          <div className="pk-title">Roadmap Review — Q3</div>
          <div className="pk-sub"><span>Thu, Jun 5</span><span className="dot" /><span>9 min recorded</span><span className="dot" /><span>4 people</span></div>
        </div>
        <span className="badge">{React.createElement(Ic.sparkles, { size: 13 })} Summarized on device</span>
        <button className="pk-btn pk-btn-ghost" style={{ marginLeft: 4 }}>{React.createElement(Ic.share, { size: 16 })} Share</button>
      </div>

      <div className="pk-sum-main">
        <section className="pk-sum-doc">
          <div className="pk-sum-eyebrow">{React.createElement(Ic.sparkles, { size: 13 })} Summary</div>
          <p className="pk-sum-lede">
            The team agreed to ship the <span className="hl">editor and handwriting layer in one Q3 release</span>, treating them as a single feature. Everything stays <span className="hl">on-device</span> — including the summary step — and Marcus will confirm the model latency before scope is locked.
          </p>

          <h2 className="pk-sum-sech">Decisions <span className="ct">3</span></h2>
          <div className="pk-decisions">
            <div className="pk-decision"><span className="mk">{React.createElement(Ic.check, { size: 13 })}</span><span className="tx">Ship the <b>editor and handwriting together</b> rather than splitting across releases.</span></div>
            <div className="pk-decision"><span className="mk">{React.createElement(Ic.check, { size: 13 })}</span><span className="tx">The summary step must run <b>locally</b> — no transcripts leave the device.</span></div>
            <div className="pk-decision"><span className="mk">{React.createElement(Ic.check, { size: 13 })}</span><span className="tx">Accept <b>~3 extra weeks</b> for on-device handwriting recognition.</span></div>
          </div>

          <h2 className="pk-sum-sech">Action items <span className="ct">3</span></h2>
          <div className="pk-actions-list">
            <div className="pk-act">
              <span className="box" />
              <span className="tx">Pull summarization latency numbers</span>
              <span className="owner"><Av who="marcus" size={22} /><span className="due">Thu</span></span>
            </div>
            <div className="pk-act">
              <span className="box" />
              <span className="tx">Confirm local-only summary with the model team</span>
              <span className="owner"><Av who="you" size={22} /><span className="due">This wk</span></span>
            </div>
            <div className="pk-act done">
              <span className="box">{React.createElement(Ic.check, { size: 12 })}</span>
              <span className="tx">Close the offline-sync bug</span>
              <span className="owner"><Av who="marcus" size={22} /><span className="due">Done</span></span>
            </div>
          </div>
        </section>

        <aside className="pk-sum-side">
          <div className="pk-side-h">Sources</div>
          <div className="pk-source">
            <span className="ic">{React.createElement(Ic.pencil, { size: 18 })}</span>
            <div><div className="t1">My notes</div><div className="t2">Typed + 3 handwritten lines</div></div>
            <span className="go">{React.createElement(Ic.arrowRight, { size: 16 })}</span>
          </div>
          <div className="pk-source">
            <span className="ic">{React.createElement(Ic.waveform, { size: 18 })}</span>
            <div><div className="t1">Full transcript</div><div className="t2">9 min · 4 speakers</div></div>
            <span className="go">{React.createElement(Ic.arrowRight, { size: 16 })}</span>
          </div>

          <div className="pk-hi-h">Key moments</div>
          <div className="pk-quote">
            <div className="q">“That's the whole promise — I'll hold the line on local-only.”</div>
            <div className="src"><Av who="priya" size={16} /> Priya R. · 12:28</div>
          </div>
          <div className="pk-quote">
            <div className="q">“The on-device model adds about three weeks.”</div>
            <div className="src"><Av who="marcus" size={16} /> Marcus K. · 12:26</div>
          </div>

          <div className="pk-ondevice">{React.createElement(Ic.bolt, { size: 14 })} Generated on this iPad · no cloud, no account</div>
        </aside>
      </div>
    </div>
  );
}

window.PkHome = PkHome;
window.PkSummary = PkSummary;
window.PkSidebar = PkSidebar;
window.Av = Av;
window.PK_PEOPLE = PK_PEOPLE;
