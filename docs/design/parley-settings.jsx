// parley-settings.jsx — right slide-over: Appearance + AI/Summarize
// Exports window.PkSettingsScene

const SI = () => window.PkIcon;

function PkToggle({ on }) {
  return <span className={"pk-switch" + (on ? " on" : "")}><span className="knob" /></span>;
}

function PkSettingsPanel() {
  const Ic = SI();
  const moods = [
    ["paper", "Paper", "Warm digital paper"],
    ["terminal", "Terminal", "Engineered, dark"],
    ["swiss", "Swiss", "Stark, gridded"],
    ["neubrutalist", "Neubrutalist", "Bold, bordered"],
  ];
  const accents = ["#3E5C50", "#8B3A2F", "#C75B39", "#27406B"];
  return (
    <div className="pk-set">
      <div className="pk-set-head">
        <div className="pk-set-title">Settings</div>
        <button className="pk-iconbtn" title="Close">{React.createElement(Ic.plus, { size: 18, style: { transform: "rotate(45deg)" } })}</button>
      </div>

      <div className="pk-set-body">
        <div className="pk-set-sec">Appearance</div>
        <div className="pk-set-label">Mood</div>
        <div className="pk-set-moods">
          {moods.map(([id, name, blurb]) => (
            <div key={id} className={"pk-set-mood srow-" + id}>
              <PkAppIcon size={34} mood={id} />
              <div className="pk-set-moodtx">
                <div className="nm">{name}</div>
                <div className="bl">{blurb}</div>
              </div>
              <span className="pk-set-check">{React.createElement(Ic.check, { size: 14 })}</span>
            </div>
          ))}
        </div>

        <div className="pk-set-label">Accent</div>
        <div className="pk-set-swatches">
          {accents.map((c, i) => (
            <span key={c} className={"pk-set-sw" + (i === 0 ? " sel" : "")} style={{ background: c }} />
          ))}
        </div>

        <div className="pk-set-row">
          <div className="pk-set-rowtx"><div className="nm">Note serif</div></div>
          <div className="pk-set-value">Newsreader {React.createElement(Ic.chevronLeft, { size: 14, style: { transform: "rotate(-90deg)", opacity: .5 } })}</div>
        </div>

        <div className="pk-set-sec">AI &amp; Summarize</div>

        <div className="pk-set-row">
          <div className="pk-set-rowtx">
            <div className="nm">Auto-summarize when I end a meeting</div>
            <div className="dsc">Draft is ready the moment you stop recording</div>
          </div>
          <PkToggle on />
        </div>

        <div className="pk-set-label">Summary tone</div>
        <div className="pk-seg pk-set-seg">
          <button>Brief</button>
          <button className="on">Balanced</button>
          <button>Detailed</button>
        </div>

        <div className="pk-set-label">Always extract</div>
        <div className="pk-set-checks">
          {[["Decisions", true], ["Action items", true], ["Open questions", true], ["Key quotes", false]].map(([lbl, on]) => (
            <div key={lbl} className={"pk-set-check-row" + (on ? " on" : "")}>
              <span className="box">{on && React.createElement(Ic.check, { size: 13 })}</span>
              <span>{lbl}</span>
            </div>
          ))}
        </div>

        <div className="pk-set-row locked">
          <div className="pk-set-rowtx">
            <div className="nm">{React.createElement(Ic.bolt, { size: 14 })} Run summaries on device only</div>
            <div className="dsc">Nothing is ever sent to the cloud</div>
          </div>
          <PkToggle on />
        </div>
      </div>
    </div>
  );
}

function PkSettingsScene() {
  return (
    <div className="pk-set-scene">
      <div className="pk-set-under"><PkHome compact /></div>
      <div className="pk-set-scrim" />
      <PkSettingsPanel />
    </div>
  );
}

window.PkSettingsScene = PkSettingsScene;
