// parley-appicon.jsx — mood-aware app icon (squircle, motif 2) + showcase board
// Exports window.PkAppIcon, window.PkIconShowcase

// superellipse "squircle" path generator (iOS-like), 0..100 box, offset+scale
function pkSquircle(ox, oy, s) {
  const k = s / 100;
  const X = (n) => +(ox + n * k).toFixed(2);
  const Y = (n) => +(oy + n * k).toFixed(2);
  return `M${X(50)},${Y(0)} C${X(9)},${Y(0)} ${X(0)},${Y(9)} ${X(0)},${Y(50)} `
       + `C${X(0)},${Y(91)} ${X(9)},${Y(100)} ${X(50)},${Y(100)} `
       + `C${X(91)},${Y(100)} ${X(100)},${Y(91)} ${X(100)},${Y(50)} `
       + `C${X(100)},${Y(9)} ${X(91)},${Y(0)} ${X(50)},${Y(0)} Z`;
}

let _pkAicN = 0;

// mood: undefined → "is-active" (tracks live mood + accent via CSS); or a fixed id
function PkAppIcon({ size = 96, mood, style }) {
  const uid = React.useMemo(() => "aic" + (++_pkAicN), []);
  const cls = "pk-app-icon " + (mood ? "is-" + mood : "is-active");
  // viewBox leaves room bottom-right for the neubrutalist hard shadow
  return (
    <svg className={cls} width={size} height={size} viewBox="0 0 116 118"
         style={style} aria-label="Parley app icon" role="img">
      <defs>
        <linearGradient id={uid + "g"} x1="0" y1="0" x2="0" y2="1">
          <stop className="aic-g0" offset="0" />
          <stop className="aic-g1" offset="1" />
        </linearGradient>
        <clipPath id={uid + "c"}><path d={pkSquircle(4, 4, 100)} /></clipPath>
      </defs>

      <path className="aic-shadow" d={pkSquircle(10, 12, 100)} />
      <path className="aic-bg" d={pkSquircle(4, 4, 100)} fill={`url(#${uid}g)`} />

      <g className="aic-grid" clipPath={`url(#${uid}c)`}>
        {[20, 36, 52, 68, 84].map((v) => (
          <line key={"h" + v} x1="4" y1={4 + v} x2="104" y2={4 + v} />
        ))}
        {[20, 36, 52, 68, 84].map((v) => (
          <line key={"v" + v} x1={4 + v} y1="4" x2={4 + v} y2="104" />
        ))}
      </g>

      <path className="aic-border" d={pkSquircle(4, 4, 100)} />

      <g className="aic-glyph" transform="translate(4,4)">
        {/* P stem + bowl, where the bowl reads as a speech turn */}
        <path className="aic-stroke" d="M37,80 L37,26 C68,26 68,54 37,54" />
        {/* speech-tail flick off the bowl */}
        <path className="aic-stroke aic-tail" d="M55,52 q5,9 -7,13" />
        {/* accent dot (shown in stark moods) */}
        <circle className="aic-dot" cx="50" cy="68" r="5" />
      </g>
    </svg>
  );
}

// ── Showcase board (its own artboard) ─────────────────────────────────
function PkIconShowcase() {
  return (
    <div className="pk-iconboard">
      <div className="pk-ib-hero">
        <PkAppIcon size={150} />
        <div className="pk-ib-lockup">
          <div className="pk-ib-wordmark">Parley</div>
          <div className="pk-ib-tag">On-device meeting companion</div>
          <div className="pk-ib-note">
            <span className="pk-ib-dot" /> The icon restyles with the active mood — change it in Settings or Tweaks.
          </div>
        </div>
      </div>

      <div className="pk-ib-platforms">
        {[
          { label: "iPhone", size: 64 },
          { label: "iPad", size: 84 },
          { label: "Mac", size: 100, mac: true },
        ].map((p) => (
          <div key={p.label} className={"pk-ib-plat" + (p.mac ? " is-mac" : "")}>
            <div className="pk-ib-wall">
              <PkAppIcon size={p.size} />
              <span className="pk-ib-applabel">Parley</span>
            </div>
            {p.mac && <div className="pk-ib-dock" />}
            <div className="pk-ib-platname">{p.label}</div>
          </div>
        ))}
      </div>

      <div className="pk-ib-moods">
        <div className="pk-ib-moodh">Across moods</div>
        <div className="pk-ib-moodrow">
          {[
            ["paper", "Paper"],
            ["terminal", "Terminal"],
            ["swiss", "Swiss"],
            ["neubrutalist", "Neubrutalist"],
          ].map(([id, label]) => (
            <div key={id} className="pk-ib-moodcell">
              <PkAppIcon size={62} mood={id} />
              <span>{label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

window.PkAppIcon = PkAppIcon;
window.PkIconShowcase = PkIconShowcase;
