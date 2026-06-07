// parley-calendar.jsx — big calendar screen (month / week / day) + day panel
// Exports window.PkCalendar

const KI = () => window.PkIcon;
const KAv = (p) => window.Av(p);

const PK_TODAY = new Date(2026, 5, 9);            // Tue, Jun 9 2026
const PK_MONTHS = ["January","February","March","April","May","June","July","August","September","October","November","December"];
const PK_DOW = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
const PK_DOW_FULL = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];

const sameDay = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const startOfWeek = (d) => addDays(d, -d.getDay());
const fmtTime = (m) => { let h = Math.floor(m / 60), mm = m % 60; const ap = h < 12 ? "am" : "pm"; h = h % 12 || 12; return mm ? `${h}:${String(mm).padStart(2,"0")}` : `${h}${ap}`; };
const fmtTimeAp = (m) => { let h = Math.floor(m / 60), mm = m % 60; const ap = h < 12 ? "AM" : "PM"; h = h % 12 || 12; return `${h}:${String(mm).padStart(2,"0")} ${ap}`; };

// ── events: June 2026 (day-of-month → list) ───────────────────────────
const E = (day, start, end, title, kind, people, note, extra) => ({ day, start, end, title, kind, people: people || [], note: note || null, ...(extra || {}) });
const PK_EVENTS = [
  E(1,  600, 660, "Sprint planning", "product", ["marcus","priya"], "Sprint 24 plan"),
  E(2,  970,1020, "1:1 — Marcus", "neutral", ["you","marcus"], "1:1 — Marcus"),
  E(3,  570, 630, "Design crit — onboarding", "product", ["you","priya"], "Design crit — onboarding"),
  E(4,  660, 750, "User interviews", "personal", ["you","priya","dana"], "User interviews — wrap-up"),
  E(5,  840, 900, "Roadmap Review — Q3", "product", ["you","alana","marcus","priya"], "Roadmap Review — Q3"),
  E(8,  540, 555, "Standup", "neutral", ["you","marcus","alana"]),
  E(8,  780, 840, "Research sync", "personal", ["you","dana"], "Research sync"),
  E(9,  540, 555, "Standup", "neutral", ["you","marcus","alana"]),
  E(9,  735, 810, "Roadmap Review — Q3", "product", ["you","alana","marcus","priya"], "Roadmap Review — Q3", { live: true }),
  E(9,  930, 990, "Design review", "product", ["you","priya"], null),
  E(10, 660, 720, "Eng all-hands", "neutral", ["you","marcus"], "Eng all-hands"),
  E(11, 960,1020, "1:1 — Priya", "neutral", ["you","priya"]),
  E(12, 900, 960, "Demo day", "personal", ["you","alana","marcus","priya"], "Demo day notes"),
  E(15, 540, 555, "Standup", "neutral", ["you","marcus"]),
  E(15, 600, 690, "Q3 kickoff", "product", ["you","alana","priya"], "Q3 kickoff"),
  E(17, 780, 870, "Board prep", "personal", ["you","alana"], "Board prep"),
  E(18, 600, 720, "Offsite planning", "product", ["you","marcus","priya"]),
  E(19, 660, 750, "User interviews — round 2", "personal", ["you","dana"], "Interviews R2"),
  E(23, 870, 960, "Perf reviews", "neutral", ["you"]),
  E(24, 780, 840, "Roadmap lock", "product", ["you","alana","marcus","priya"], "Roadmap lock"),
  E(25, 960,1020, "1:1 — Marcus", "neutral", ["you","marcus"], "1:1 — Marcus"),
  E(30, 600, 660, "Month review", "personal", ["you","alana"], "Month review"),
];
const eventsForDay = (d) => (d.getMonth() === 5 ? PK_EVENTS.filter((e) => e.day === d.getDate()) : []).sort((a, b) => a.start - b.start);
const dayHasNote = (d) => eventsForDay(d).some((e) => e.note);

// quick notes jotted onto days (standalone, not from a meeting)
const PK_DAYNOTES = { 9: "Ask Marcus for the latency spreadsheet before standup.", 11: "Bring the onboarding redraw to the 1:1.", 16: "Pay invoice · book offsite venue" };

const KIND_LABEL = { product: "Product", neutral: "Meeting", personal: "Personal" };

// ── time-grid window ──────────────────────────────────────────────────
const PK_H0 = 8, PK_H1 = 20;                      // 8am – 8pm
const HOURS = Array.from({ length: PK_H1 - PK_H0 + 1 }, (_, i) => PK_H0 + i);

function EventBlock({ ev, pxPerMin, onPick }) {
  const top = (ev.start - PK_H0 * 60) * pxPerMin;
  const h = Math.max(22, (ev.end - ev.start) * pxPerMin);
  return (
    <div className={"pk-cal-block k-" + ev.kind + (ev.live ? " live" : "")}
         style={{ top, height: h }} onClick={() => onPick && onPick(ev)}>
      <div className="bt">{ev.live && <span className="pk-rec-dot" />}{ev.title}</div>
      <div className="bm">{fmtTime(ev.start)}–{fmtTime(ev.end)}{ev.note && <span className="lk">{React.createElement(KI().link, { size: 11 })}</span>}</div>
    </div>
  );
}

// ── MONTH ─────────────────────────────────────────────────────────────
function MonthGrid({ cursor, selected, onSelect }) {
  const Ic = KI();
  const first = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
  const gridStart = startOfWeek(first);
  const cells = Array.from({ length: 35 }, (_, i) => addDays(gridStart, i));
  return (
    <div className="pk-cal-month">
      <div className="pk-cal-dow">{PK_DOW.map((d) => <div key={d} className="pk-cal-dowc">{d}</div>)}</div>
      <div className="pk-cal-grid">
        {cells.map((d, i) => {
          const out = d.getMonth() !== cursor.getMonth();
          const evs = eventsForDay(d);
          const note = PK_DAYNOTES[d.getMonth() === 5 ? d.getDate() : -1];
          const isToday = sameDay(d, PK_TODAY);
          const isSel = sameDay(d, selected);
          return (
            <div key={i} className={"pk-cal-cell" + (out ? " out" : "") + (isSel ? " sel" : "")} onClick={() => onSelect(d)}>
              <div className="pk-cal-daynum-row">
                <span className={"pk-cal-daynum" + (isToday ? " today" : "")}>{d.getDate()}</span>
                {note && <span className="pk-cal-noteflag" title="Quick note">{React.createElement(Ic.pencil, { size: 11 })}</span>}
              </div>
              <div className="pk-cal-evs">
                {evs.slice(0, 3).map((e, k) => (
                  <div key={k} className={"pk-cal-chip k-" + e.kind + (e.live ? " live" : "")}>
                    {e.live ? <span className="pk-rec-dot" /> : <span className="tk">{fmtTime(e.start)}</span>}
                    <span className="ct">{e.title}</span>
                    {e.note && React.createElement(Ic.link, { size: 10, style: { flex: "0 0 auto", opacity: .65 } })}
                  </div>
                ))}
                {evs.length > 3 && <div className="pk-cal-more">+{evs.length - 3} more</div>}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ── WEEK ──────────────────────────────────────────────────────────────
function WeekGrid({ cursor, selected, onSelect, onPick }) {
  const days = Array.from({ length: 7 }, (_, i) => addDays(startOfWeek(cursor), i));
  const pxPerMin = 52 / 60;
  return (
    <div className="pk-cal-week">
      <div className="pk-cal-weekhead">
        <div className="pk-cal-gutter" />
        {days.map((d, i) => {
          const isToday = sameDay(d, PK_TODAY);
          return (
            <div key={i} className={"pk-cal-wh" + (sameDay(d, selected) ? " sel" : "")} onClick={() => onSelect(d)}>
              <span className="wd">{PK_DOW[d.getDay()]}</span>
              <span className={"dn" + (isToday ? " today" : "")}>{d.getDate()}</span>
            </div>
          );
        })}
      </div>
      <div className="pk-cal-weekbody">
        <div className="pk-cal-gutter">
          {HOURS.map((h) => <div key={h} className="pk-cal-hr"><span>{fmtTime(h * 60)}</span></div>)}
        </div>
        {days.map((d, i) => (
          <div key={i} className={"pk-cal-col" + (sameDay(d, PK_TODAY) ? " today" : "")}>
            {HOURS.map((h) => <div key={h} className="pk-cal-slot" />)}
            {eventsForDay(d).map((e, k) => <EventBlock key={k} ev={e} pxPerMin={pxPerMin} onPick={onPick} />)}
          </div>
        ))}
      </div>
    </div>
  );
}

// ── DAY ───────────────────────────────────────────────────────────────
function DayGrid({ selected, onPick }) {
  const pxPerMin = 66 / 60;
  return (
    <div className="pk-cal-day">
      <div className="pk-cal-weekbody day">
        <div className="pk-cal-gutter">
          {HOURS.map((h) => <div key={h} className="pk-cal-hr tall"><span>{fmtTime(h * 60)}</span></div>)}
        </div>
        <div className={"pk-cal-col wide" + (sameDay(selected, PK_TODAY) ? " today" : "")}>
          {HOURS.map((h) => <div key={h} className="pk-cal-slot tall" />)}
          {eventsForDay(selected).map((e, k) => <EventBlock key={k} ev={e} pxPerMin={pxPerMin} onPick={onPick} />)}
        </div>
      </div>
    </div>
  );
}

// ── DAY PANEL (right rail) — events + linked notes + quick note ───────
function DayPanel({ selected }) {
  const Ic = KI();
  const evs = eventsForDay(selected);
  const note = PK_DAYNOTES[selected.getMonth() === 5 ? selected.getDate() : -1];
  const isToday = sameDay(selected, PK_TODAY);
  return (
    <aside className="pk-cal-panel">
      <div className="pk-cal-panel-head">
        <div className="pk-cal-panel-dow">{isToday ? "Today" : PK_DOW_FULL[selected.getDay()]}</div>
        <div className="pk-cal-panel-date">{PK_MONTHS[selected.getMonth()]} {selected.getDate()}</div>
      </div>

      <button className="pk-cal-newev"><span className="pl">{React.createElement(Ic.plus, { size: 15 })}</span> New event</button>

      <div className="pk-cal-panel-sec">{evs.length} event{evs.length !== 1 ? "s" : ""}</div>
      <div className="pk-cal-panel-list">
        {evs.length === 0 && <div className="pk-cal-empty">Nothing scheduled.</div>}
        {evs.map((e, k) => (
          <div key={k} className={"pk-cal-item k-" + e.kind}>
            <div className="rail" />
            <div className="bd">
              <div className="t1">{e.live && <span className="pk-rec-dot" />}{e.title}</div>
              <div className="t2">{fmtTimeAp(e.start)} – {fmtTimeAp(e.end)} · {KIND_LABEL[e.kind]}</div>
              <div className="t3">
                {e.people.length > 0 && (
                  <span className="ppl">{e.people.slice(0, 4).map((w, j) => <KAv key={j} who={w} size={18} />)}</span>
                )}
                {e.note ? (
                  <span className="notelink">{React.createElement(Ic.pencil, { size: 12 })} {e.note}<span className="go">{React.createElement(Ic.arrowRight, { size: 13 })}</span></span>
                ) : (
                  <button className="linkbtn">{React.createElement(Ic.link, { size: 12 })} Link a note</button>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="pk-cal-panel-sec">Quick note</div>
      {note && (
        <div className="pk-cal-quicknote">
          <span className="qn-tack">{React.createElement(Ic.pencil, { size: 12 })}</span>
          <span>{note}</span>
        </div>
      )}
      <div className="pk-cal-jot">
        <input placeholder={`Jot a note for ${PK_MONTHS[selected.getMonth()].slice(0,3)} ${selected.getDate()}…`} readOnly />
        <button className="pk-cal-jot-add">{React.createElement(Ic.plus, { size: 16 })}</button>
      </div>
      <div className="pk-cal-panel-foot">{React.createElement(Ic.bolt, { size: 12 })} Notes &amp; events stay on this iPad</div>
    </aside>
  );
}

// ── SCREEN ────────────────────────────────────────────────────────────
function PkCalendar() {
  const Ic = KI();
  const [view, setView] = React.useState("month");
  const [cursor, setCursor] = React.useState(new Date(2026, 5, 9));
  const [selected, setSelected] = React.useState(new Date(2026, 5, 9));

  const step = (dir) => {
    if (view === "month") setCursor(new Date(cursor.getFullYear(), cursor.getMonth() + dir, 1));
    else setCursor(addDays(cursor, dir * (view === "week" ? 7 : 1)));
  };
  const goToday = () => { setCursor(new Date(PK_TODAY)); setSelected(new Date(PK_TODAY)); };
  const pickDay = (d) => { setSelected(d); if (view !== "month") setCursor(d); };

  // header title
  let title;
  if (view === "month") title = `${PK_MONTHS[cursor.getMonth()]} ${cursor.getFullYear()}`;
  else if (view === "week") {
    const ws = startOfWeek(cursor), we = addDays(ws, 6);
    title = ws.getMonth() === we.getMonth()
      ? `${PK_MONTHS[ws.getMonth()]} ${ws.getDate()}–${we.getDate()}`
      : `${PK_MONTHS[ws.getMonth()].slice(0,3)} ${ws.getDate()} – ${PK_MONTHS[we.getMonth()].slice(0,3)} ${we.getDate()}`;
  } else title = `${PK_DOW_FULL[selected.getDay()]}, ${PK_MONTHS[selected.getMonth()]} ${selected.getDate()}`;

  return (
    <div className="pk-cal-screen">
      <PkSidebar active="calendar" />

      <main className="pk-cal-main">
        <header className="pk-cal-head">
          <div className="pk-cal-head-l">
            <h1 className="pk-cal-title">{title}</h1>
            <div className="pk-cal-nav">
              <button className="pk-iconbtn" onClick={() => step(-1)} title="Previous">{React.createElement(Ic.chevronLeft, { size: 18 })}</button>
              <button className="pk-cal-today" onClick={goToday}>Today</button>
              <button className="pk-iconbtn" onClick={() => step(1)} title="Next">{React.createElement(Ic.chevronLeft, { size: 18, style: { transform: "rotate(180deg)" } })}</button>
            </div>
          </div>
          <div className="pk-cal-head-r">
            <div className="pk-seg pk-cal-views">
              {["month","week","day"].map((v) => (
                <button key={v} className={view === v ? "on" : ""} onClick={() => setView(v)}>{v[0].toUpperCase() + v.slice(1)}</button>
              ))}
            </div>
            <button className="pk-btn pk-btn-summary pk-cal-add">{React.createElement(Ic.plus, { size: 16 })} New event</button>
          </div>
        </header>

        <div className="pk-cal-stage">
          {view === "month" && <MonthGrid cursor={cursor} selected={selected} onSelect={pickDay} />}
          {view === "week" && <WeekGrid cursor={cursor} selected={selected} onSelect={pickDay} onPick={(e) => {}} />}
          {view === "day" && <DayGrid selected={selected} onPick={(e) => {}} />}
        </div>
      </main>

      <DayPanel selected={selected} />
    </div>
  );
}

window.PkCalendar = PkCalendar;
