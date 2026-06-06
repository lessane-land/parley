// parley-icons.jsx — SF Symbols-style line icons (stroke, 1.7 weight)
// Exports window.PkIcon : { name -> component }

const PkI = ({ d, size = 18, sw = 1.7, fill, children, vb = 24, style }) => (
  <svg width={size} height={size} viewBox={`0 0 ${vb} ${vb}`} fill={fill || 'none'}
       stroke={fill ? 'none' : 'currentColor'} strokeWidth={sw}
       strokeLinecap="round" strokeLinejoin="round" style={style} aria-hidden="true">
    {d ? <path d={d} /> : children}
  </svg>
);

const PkIcon = {
  chevronLeft: (p) => <PkI {...p} d="M15 4l-8 8 8 8" />,
  cloudCheck: (p) => (
    <PkI {...p}>
      <path d="M7 18h9.5a3.5 3.5 0 0 0 .4-6.98A5 5 0 0 0 7.6 9.4 4 4 0 0 0 7 18Z" />
      <path d="M10 13.6l1.7 1.7 3-3.4" />
    </PkI>
  ),
  flag: (p) => (
    <PkI {...p}>
      <path d="M6 21V4" />
      <path d="M6 5h10.5l-1.8 3.2 1.8 3.2H6" />
    </PkI>
  ),
  sparkles: (p) => (
    <PkI {...p}>
      <path d="M12 4.2l1.5 4 4 1.5-4 1.5-1.5 4-1.5-4-4-1.5 4-1.5 1.5-4Z" />
      <path d="M18.5 14.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7.7-1.8Z" />
    </PkI>
  ),
  mic: (p) => (
    <PkI {...p}>
      <rect x="9" y="3" width="6" height="11" rx="3" />
      <path d="M6 11a6 6 0 0 0 12 0M12 17v4M9 21h6" />
    </PkI>
  ),
  plus: (p) => <PkI {...p} d="M12 5v14M5 12h14" />,
  search: (p) => <PkI {...p}><circle cx="11" cy="11" r="6.5" /><path d="M20 20l-3.8-3.8" /></PkI>,
  calendar: (p) => (
    <PkI {...p}>
      <rect x="3.5" y="5" width="17" height="16" rx="2.5" />
      <path d="M3.5 9.5h17M8 3v4M16 3v4" />
    </PkI>
  ),
  pencil: (p) => (
    <PkI {...p}>
      <path d="M4 20l1-4L16 5l3 3L8 19l-4 1Z" />
      <path d="M14 7l3 3" />
    </PkI>
  ),
  textCursor: (p) => (
    <PkI {...p}>
      <path d="M12 5.5v13M9 5.5h6M9 18.5h6" />
    </PkI>
  ),
  list: (p) => <PkI {...p}><path d="M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01" /></PkI>,
  image: (p) => (
    <PkI {...p}>
      <rect x="3.5" y="5" width="17" height="14" rx="2.5" />
      <circle cx="8.5" cy="10" r="1.8" />
      <path d="M5 17l4.5-4.5 3.5 3.5 2.5-2.5 4 4" />
    </PkI>
  ),
  send: (p) => <PkI {...p}><path d="M12 19V6M6 11l6-6 6 6" /></PkI>,
  gear: (p) => (
    <PkI {...p}>
      <circle cx="12" cy="12" r="3.2" />
      <path d="M12 3.5v2.2M12 18.3v2.2M4.6 7.8l1.9 1.1M17.5 15.1l1.9 1.1M4.6 16.2l1.9-1.1M17.5 8.9l1.9-1.1" />
    </PkI>
  ),
  check: (p) => <PkI {...p} d="M5 12.5l4.5 4.5L19 7" />,
  checkCircle: (p) => <PkI {...p}><circle cx="12" cy="12" r="8.5" /><path d="M8.5 12.2l2.4 2.4 4.6-5" /></PkI>,
  circle: (p) => <PkI {...p}><circle cx="12" cy="12" r="8.5" /></PkI>,
  arrowRight: (p) => <PkI {...p} d="M5 12h14M13 6l6 6-6 6" />,
  arrowUpRight: (p) => <PkI {...p} d="M7 17L17 7M8 7h9v9" />,
  clock: (p) => <PkI {...p}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></PkI>,
  share: (p) => (
    <PkI {...p}>
      <path d="M12 15V4M8.5 7.5L12 4l3.5 3.5" />
      <path d="M6 12v6.5A1.5 1.5 0 0 0 7.5 20h9a1.5 1.5 0 0 0 1.5-1.5V12" />
    </PkI>
  ),
  dots: (p) => <PkI {...p} fill="currentColor"><circle cx="5" cy="12" r="1.7" /><circle cx="12" cy="12" r="1.7" /><circle cx="19" cy="12" r="1.7" /></PkI>,
  person: (p) => <PkI {...p}><circle cx="12" cy="8" r="3.7" /><path d="M5.5 20a6.5 6.5 0 0 1 13 0" /></PkI>,
  folder: (p) => <PkI {...p}><path d="M3.5 7.5A1.5 1.5 0 0 1 5 6h4l2 2.2h8a1.5 1.5 0 0 1 1.5 1.5V18a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 18Z" /></PkI>,
  bolt: (p) => <PkI {...p} d="M13 3L5 13h5l-1 8 8-10h-5l1-8Z" />,
  link: (p) => (
    <PkI {...p}>
      <path d="M10 14a3.5 3.5 0 0 0 5 0l2.5-2.5a3.5 3.5 0 0 0-5-5L11 8" />
      <path d="M14 10a3.5 3.5 0 0 0-5 0L6.5 12.5a3.5 3.5 0 0 0 5 5L13 16" />
    </PkI>
  ),
  waveform: (p) => (
    <PkI {...p} sw={p.sw || 1.9}>
      <path d="M4 12v0M8 8v8M12 4.5v15M16 9v6M20 12v0" />
    </PkI>
  ),
};

window.PkIcon = PkIcon;
