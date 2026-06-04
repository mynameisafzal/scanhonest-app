// ScanHonest — all 10 screen components
// Original design. Brand: deep forest green. Anti-dark-pattern UX.

const SH = {
  primary: '#1B4332',
  secondary: '#2D6A4F',
  accent: '#74C69D',
  accentSoft: '#D8F0E2',
  bg: '#F8F9FA',
  surface: '#FFFFFF',
  text: '#1A1A1A',
  muted: '#6C757D',
  hairline: 'rgba(60,60,67,0.12)',
  danger: '#DC3545',
  gold: '#F4A261',
  goldSoft: '#FCE8D4',
  warn: '#E2A044',
};

const FONT = '-apple-system, "SF Pro Display", "SF Pro Text", system-ui, sans-serif';
const MONO = '"SF Mono", "JetBrains Mono", ui-monospace, Menlo, monospace';

// ─────────────────────────────────────────────────────────────
// Shared little bits
// ─────────────────────────────────────────────────────────────
const Anno = ({ children, style }) => (
  <div style={{
    position: 'absolute', fontFamily: MONO, fontSize: 9,
    color: '#9a8a72', letterSpacing: 0.2, lineHeight: 1.3,
    pointerEvents: 'none', ...style,
  }}>{children}</div>
);

const Dot = ({ active }) => (
  <div style={{
    width: active ? 22 : 6, height: 6, borderRadius: 999,
    background: active ? SH.primary : 'rgba(27,67,50,0.18)',
    transition: 'all .3s',
  }} />
);

// SF-symbol-style icons (original line glyphs)
const Icon = {
  scan: (c = SH.primary, s = 22) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none">
      <path d="M3 7V5a2 2 0 012-2h2M21 7V5a2 2 0 00-2-2h-2M3 17v2a2 2 0 002 2h2M21 17v2a2 2 0 01-2 2h-2" stroke={c} strokeWidth="1.8" strokeLinecap="round"/>
      <path d="M7 12h10" stroke={c} strokeWidth="1.8" strokeLinecap="round"/>
    </svg>
  ),
  search: (c = SH.muted, s = 18) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="7" stroke={c} strokeWidth="1.8"/><path d="M20 20l-3.5-3.5" stroke={c} strokeWidth="1.8" strokeLinecap="round"/></svg>
  ),
  gear: (c = SH.muted, s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="3" stroke={c} strokeWidth="1.6"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>
  ),
  photos: (c = SH.primary, s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><rect x="3" y="5" width="18" height="14" rx="2" stroke={c} strokeWidth="1.8"/><circle cx="8.5" cy="10" r="1.5" fill={c}/><path d="M3 17l5-4 4 3 3-2 6 4" stroke={c} strokeWidth="1.8" strokeLinejoin="round" fill="none"/></svg>
  ),
  check: (c = SH.accent, s = 16) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M5 12.5l4.5 4.5L19 7" stroke={c} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"/></svg>
  ),
  share: (c = SH.primary, s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 3v13M12 3l-4 4M12 3l4 4M5 13v6a2 2 0 002 2h10a2 2 0 002-2v-6" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg>
  ),
  flash: (c = '#fff', s = 22) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z" stroke={c} strokeWidth="1.8" strokeLinejoin="round"/></svg>
  ),
  close: (c = '#fff', s = 22) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M6 6l12 12M18 6L6 18" stroke={c} strokeWidth="2" strokeLinecap="round"/></svg>
  ),
  crop: (c = SH.text, s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M6 2v16h16M2 6h16v16" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>
  ),
  rotate: (c = SH.text, s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M21 12a9 9 0 11-3-6.7M21 4v5h-5" stroke={c} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/></svg>
  ),
  enhance: (c = SH.text, s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 3l1.8 4.5L18 9l-4.2 1.5L12 15l-1.8-4.5L6 9l4.2-1.5z" stroke={c} strokeWidth="1.6" strokeLinejoin="round"/><path d="M19 16l.8 2L22 19l-2.2 1L19 22l-.8-2L16 19l2.2-1z" stroke={c} strokeWidth="1.4" strokeLinejoin="round"/></svg>
  ),
  filter: (c = SH.text, s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="9" cy="12" r="6" stroke={c} strokeWidth="1.6"/><circle cx="15" cy="12" r="6" stroke={c} strokeWidth="1.6"/></svg>
  ),
  retake: (c = SH.text, s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="12" cy="13" r="4" stroke={c} strokeWidth="1.6"/><path d="M3 7h3l1.5-2h9L18 7h3v11H3V7z" stroke={c} strokeWidth="1.6" strokeLinejoin="round"/></svg>
  ),
  lock: (c = SH.muted, s = 16) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><rect x="5" y="11" width="14" height="9" rx="2" stroke={c} strokeWidth="1.6"/><path d="M8 11V8a4 4 0 018 0v3" stroke={c} strokeWidth="1.6"/></svg>
  ),
  text: (c = SH.muted, s = 18) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M5 6h14M12 6v14M9 20h6" stroke={c} strokeWidth="1.8" strokeLinecap="round"/></svg>
  ),
  cloud: (c = SH.primary, s = 22) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M7 18h10a4 4 0 100-8 6 6 0 00-11.7 1.3A4 4 0 007 18z" stroke={c} strokeWidth="1.6" strokeLinejoin="round"/></svg>
  ),
  back: (c = SH.primary, s = 18) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M15 5l-7 7 7 7" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
  ),
  more: (c = SH.text, s = 20) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><circle cx="5" cy="12" r="1.6" fill={c}/><circle cx="12" cy="12" r="1.6" fill={c}/><circle cx="19" cy="12" r="1.6" fill={c}/></svg>
  ),
  plus: (c = SH.primary, s = 18) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 5v14M5 12h14" stroke={c} strokeWidth="2" strokeLinecap="round"/></svg>
  ),
  pdf: (c = SH.primary, s = 22) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M7 3h7l5 5v13H7V3z" stroke={c} strokeWidth="1.6" strokeLinejoin="round"/><path d="M14 3v5h5" stroke={c} strokeWidth="1.6"/><text x="12" y="17" textAnchor="middle" fontSize="5" fontWeight="700" fill={c} fontFamily="-apple-system">PDF</text></svg>
  ),
};

// Document thumbnail placeholder — striped paper look
const DocThumb = ({ pages = 1, tone = 'paper', label, style }) => {
  const bg = tone === 'paper' ? '#fff' : '#F0EBE2';
  return (
    <div style={{
      background: bg, borderRadius: 6, position: 'relative',
      boxShadow: '0 1px 3px rgba(20,30,25,0.08), 0 4px 16px rgba(20,30,25,0.06), inset 0 0 0 1px rgba(0,0,0,0.04)',
      overflow: 'hidden', ...style,
    }}>
      {/* striped fake content */}
      <div style={{ padding: '14% 12%', display: 'flex', flexDirection: 'column', gap: '4%' }}>
        <div style={{ height: 4, background: 'rgba(27,67,50,0.5)', borderRadius: 1, width: '55%' }} />
        <div style={{ height: 2, background: 'rgba(60,60,67,0.18)', width: '90%' }} />
        <div style={{ height: 2, background: 'rgba(60,60,67,0.18)', width: '85%' }} />
        <div style={{ height: 2, background: 'rgba(60,60,67,0.18)', width: '92%' }} />
        <div style={{ height: 2, background: 'rgba(60,60,67,0.18)', width: '70%' }} />
        <div style={{ height: 6 }} />
        <div style={{ height: 2, background: 'rgba(60,60,67,0.18)', width: '88%' }} />
        <div style={{ height: 2, background: 'rgba(60,60,67,0.18)', width: '60%' }} />
        <div style={{ height: 2, background: 'rgba(60,60,67,0.18)', width: '78%' }} />
      </div>
      {pages > 1 && (
        <div style={{
          position: 'absolute', top: 6, right: 6, padding: '2px 6px',
          background: 'rgba(27,67,50,0.92)', color: '#fff',
          fontFamily: MONO, fontSize: 9, borderRadius: 4, letterSpacing: 0.2,
        }}>{pages}p</div>
      )}
      {label && (
        <div style={{ position: 'absolute', left: 8, bottom: 6, fontFamily: MONO, fontSize: 8, color: SH.muted, opacity: 0.5 }}>{label}</div>
      )}
    </div>
  );
};

// Top-of-screen status bar (light)
const TopBar = ({ dark = false }) => {
  const c = dark ? '#fff' : '#000';
  return (
    <div style={{
      height: 54, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '17px 28px 0', position: 'relative', zIndex: 5,
    }}>
      <div style={{ fontFamily: FONT, fontSize: 16, fontWeight: 600, color: c }}>9:41</div>
      <div style={{ width: 100 }} />
      <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
        <svg width="17" height="11" viewBox="0 0 17 11"><rect x="0" y="6" width="3" height="5" rx="0.5" fill={c}/><rect x="4.5" y="4" width="3" height="7" rx="0.5" fill={c}/><rect x="9" y="2" width="3" height="9" rx="0.5" fill={c}/><rect x="13.5" y="0" width="3" height="11" rx="0.5" fill={c}/></svg>
        <svg width="24" height="11" viewBox="0 0 24 11"><rect x="0.5" y="0.5" width="20" height="10" rx="3" stroke={c} strokeOpacity="0.4" fill="none"/><rect x="2" y="2" width="17" height="7" rx="2" fill={c}/><rect x="21.5" y="3.5" width="1.5" height="4" rx="0.5" fill={c} opacity="0.4"/></svg>
      </div>
    </div>
  );
};

const HomeIndicator = ({ dark = false }) => (
  <div style={{
    position: 'absolute', bottom: 8, left: 0, right: 0,
    display: 'flex', justifyContent: 'center', pointerEvents: 'none', zIndex: 60,
  }}>
    <div style={{ width: 134, height: 5, borderRadius: 999, background: dark ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.3)' }} />
  </div>
);

// Phone shell
const Phone = ({ children, dark = false, w = 390, h = 780, bg }) => (
  <div style={{
    width: w, height: h, borderRadius: 44, position: 'relative',
    background: bg || (dark ? '#000' : SH.bg),
    overflow: 'hidden',
    boxShadow: '0 30px 60px rgba(20,30,25,0.16), 0 0 0 1px rgba(0,0,0,0.08), inset 0 0 0 6px #1a1a1a, inset 0 0 0 8px #2a2a2a',
    fontFamily: FONT, color: SH.text,
    WebkitFontSmoothing: 'antialiased',
  }}>
    {/* dynamic island */}
    <div style={{
      position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
      width: 118, height: 34, borderRadius: 20, background: '#000', zIndex: 50,
    }} />
    <TopBar dark={dark} />
    <div style={{ height: h - 54 - 8, position: 'relative', overflow: 'hidden' }}>{children}</div>
    <HomeIndicator dark={dark} />
  </div>
);

// Primary button
const Btn = ({ children, variant = 'primary', icon, style }) => {
  const styles = {
    primary: { background: SH.primary, color: '#fff', border: 'none' },
    accent:  { background: SH.accent, color: SH.primary, border: 'none' },
    outline: { background: 'transparent', color: SH.primary, border: `1.5px solid ${SH.primary}` },
    ghost:   { background: 'rgba(27,67,50,0.06)', color: SH.primary, border: 'none' },
  }[variant];
  return (
    <div style={{
      height: 56, borderRadius: 28,
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
      fontFamily: FONT, fontSize: 17, fontWeight: 600, letterSpacing: -0.2,
      ...styles, ...style,
    }}>
      {icon}{children}
    </div>
  );
};

// ─────────────────────────────────────────────────────────────
// SCREEN 1A — Onboarding slide 1
// ─────────────────────────────────────────────────────────────
function ScreenOnboard1() {
  return (
    <Phone>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '0 28px' }}>
        {/* Wordmark */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6 }}>
          <div style={{ width: 24, height: 24, borderRadius: 7, background: SH.primary, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            {Icon.check('#74C69D', 14)}
          </div>
          <div style={{ fontSize: 15, fontWeight: 600, letterSpacing: -0.2, color: SH.text }}>ScanHonest</div>
        </div>

        {/* Hero */}
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ width: '100%', aspectRatio: '1/1', position: 'relative' }}>
            {/* desk */}
            <div style={{ position: 'absolute', inset: 0, borderRadius: 24, background: 'linear-gradient(180deg, #EDE6D8 0%, #E0D5BF 100%)', overflow: 'hidden' }}>
              {/* paper sheets stacked */}
              <div style={{ position: 'absolute', top: '18%', left: '14%', width: '52%', height: '64%', background: '#fff', borderRadius: 4, boxShadow: '0 6px 20px rgba(40,30,15,0.15)', transform: 'rotate(-6deg)' }}>
                <div style={{ padding: '14% 14%', display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <div style={{ height: 4, width: '60%', background: SH.primary, borderRadius: 1 }} />
                  <div style={{ height: 3 }} />
                  {[0,1,2,3,4].map(i => <div key={i} style={{ height: 2.5, background: 'rgba(60,60,67,0.18)', width: `${85 - i*4}%` }} />)}
                </div>
              </div>
              <div style={{ position: 'absolute', top: '24%', right: '12%', width: '50%', height: '60%', background: '#fff', borderRadius: 4, boxShadow: '0 6px 20px rgba(40,30,15,0.18)', transform: 'rotate(8deg)' }}>
                <div style={{ padding: '14% 14%', display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <div style={{ height: 4, width: '70%', background: SH.primary, borderRadius: 1 }} />
                  <div style={{ height: 3 }} />
                  {[0,1,2,3,4,5].map(i => <div key={i} style={{ height: 2.5, background: 'rgba(60,60,67,0.18)', width: `${90 - i*5}%` }} />)}
                </div>
              </div>
              {/* phone capturing */}
              <div style={{ position: 'absolute', bottom: '8%', left: '50%', transform: 'translateX(-50%)', width: '34%', aspectRatio: '9/19', borderRadius: 22, background: SH.primary, boxShadow: '0 8px 24px rgba(20,30,25,0.3)', padding: 6 }}>
                <div style={{ width: '100%', height: '100%', borderRadius: 16, background: '#0a1a12', position: 'relative', overflow: 'hidden' }}>
                  {/* camera frame */}
                  {['tl','tr','bl','br'].map((p, i) => {
                    const pos = { tl: { top: 8, left: 8 }, tr: { top: 8, right: 8 }, bl: { bottom: 8, left: 8 }, br: { bottom: 8, right: 8 } }[p];
                    const rot = { tl: 0, tr: 90, br: 180, bl: 270 }[p];
                    return (
                      <div key={p} style={{ position: 'absolute', ...pos, width: 10, height: 10, borderTop: `2px solid ${SH.accent}`, borderLeft: `2px solid ${SH.accent}`, transform: `rotate(${rot}deg)` }} />
                    );
                  })}
                </div>
              </div>
            </div>
            <Anno style={{ top: -10, right: 6 }}>// editorial illustration · paper + capture metaphor</Anno>
          </div>
        </div>

        {/* Copy */}
        <div style={{ marginTop: 8 }}>
          <h1 style={{ fontSize: 32, fontWeight: 700, letterSpacing: -0.8, lineHeight: 1.1, margin: 0, color: SH.text, textWrap: 'pretty' }}>
            Scan anything.<br/>Keep everything.
          </h1>
          <p style={{ fontSize: 15, lineHeight: 1.45, color: SH.muted, marginTop: 12, marginBottom: 0, textWrap: 'pretty' }}>
            No tricks. No surprise paywalls. Your first <span style={{ color: SH.text, fontWeight: 600 }}>5 scans are completely free</span> — every month, forever.
          </p>
        </div>

        {/* Progress dots */}
        <div style={{ display: 'flex', gap: 6, justifyContent: 'center', marginTop: 18, marginBottom: 14 }}>
          <Dot active /><Dot /><Dot />
        </div>

        {/* Actions */}
        <Btn variant="primary">Get Started</Btn>
        <div style={{ textAlign: 'center', fontSize: 14, color: SH.muted, marginTop: 14, marginBottom: 8 }}>
          <span>I already have an account</span>
        </div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 1B — Onboarding slide 2 (HONEST PRICING)
// ─────────────────────────────────────────────────────────────
function ScreenOnboard2() {
  return (
    <Phone>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '0 24px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6, padding: '0 4px' }}>
          <div style={{ width: 24, height: 24, borderRadius: 7, background: SH.primary, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            {Icon.check('#74C69D', 14)}
          </div>
          <div style={{ fontSize: 15, fontWeight: 600, letterSpacing: -0.2 }}>ScanHonest</div>
          <div style={{ marginLeft: 'auto', fontSize: 14, color: SH.muted }}>Skip</div>
        </div>

        <div style={{ marginTop: 22, padding: '0 4px' }}>
          <h1 style={{ fontSize: 30, fontWeight: 700, letterSpacing: -0.8, lineHeight: 1.1, margin: 0 }}>
            Honest pricing,<br/>always.
          </h1>
          <p style={{ fontSize: 14.5, lineHeight: 1.45, color: SH.muted, marginTop: 10, marginBottom: 0 }}>
            We show you both options up front. Pick whatever's right — or stay free forever.
          </p>
        </div>

        {/* Two cards equal weight */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 22 }}>
          {/* one-time */}
          <div style={{
            background: SH.surface, borderRadius: 18, padding: 18,
            border: `2px solid ${SH.primary}`,
            boxShadow: '0 1px 2px rgba(27,67,50,0.04), 0 8px 24px rgba(27,67,50,0.08), 0 2px 8px rgba(27,67,50,0.04)',
            position: 'relative',
          }}>
            <div style={{
              position: 'absolute', top: -10, left: 16, padding: '4px 10px',
              background: SH.primary, color: '#fff', borderRadius: 999,
              fontFamily: MONO, fontSize: 10, letterSpacing: 0.4, textTransform: 'uppercase',
            }}>Most popular</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <div style={{ fontSize: 36, fontWeight: 700, letterSpacing: -1, color: SH.primary, fontFamily: FONT }}>$4.99</div>
              <div style={{ fontSize: 14, color: SH.muted }}>once</div>
            </div>
            <div style={{ fontSize: 14, color: SH.text, marginTop: 4, fontWeight: 500 }}>Pay once, yours forever.</div>
            <div style={{ fontSize: 13, color: SH.muted, marginTop: 2 }}>No recurring charges. Ever.</div>
          </div>

          {/* monthly */}
          <div style={{
            background: SH.surface, borderRadius: 18, padding: 18,
            border: `1px solid ${SH.hairline}`,
          }}>
            <div style={{
              position: 'absolute', marginTop: -2, padding: '3px 10px',
              background: SH.bg, color: SH.muted, borderRadius: 999,
              fontFamily: MONO, fontSize: 10, letterSpacing: 0.4, textTransform: 'uppercase',
              transform: 'translate(-6px, -28px)', border: `1px solid ${SH.hairline}`,
            }}>Try first</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <div style={{ fontSize: 36, fontWeight: 700, letterSpacing: -1, color: SH.text, fontFamily: FONT }}>$1.99</div>
              <div style={{ fontSize: 14, color: SH.muted }}>/ month</div>
            </div>
            <div style={{ fontSize: 14, color: SH.text, marginTop: 4, fontWeight: 500 }}>Try for a month, cancel anytime.</div>
            <div style={{ fontSize: 13, color: SH.muted, marginTop: 2 }}>Both prices shown — no hiding.</div>
          </div>
        </div>

        <div style={{
          marginTop: 'auto', marginBottom: 14, padding: 12,
          background: SH.accentSoft, borderRadius: 12,
          fontSize: 13, color: SH.primary, lineHeight: 1.4, textAlign: 'center',
        }}>
          You can upgrade anytime. Or never.<br/>
          <strong>5 free scans every month, forever.</strong>
        </div>

        <div style={{ display: 'flex', gap: 6, justifyContent: 'center', marginBottom: 12 }}>
          <Dot /><Dot active /><Dot />
        </div>

        <Btn variant="primary" style={{ marginBottom: 8 }}>Continue</Btn>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 1C — Permissions
// ─────────────────────────────────────────────────────────────
function ScreenPermissions() {
  const PermRow = ({ icon, title, body, required }) => (
    <div style={{
      display: 'flex', gap: 14, padding: 16,
      background: SH.surface, borderRadius: 16,
      border: `1px solid ${SH.hairline}`,
    }}>
      <div style={{
        width: 44, height: 44, borderRadius: 11, flexShrink: 0,
        background: SH.accentSoft, display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>{icon}</div>
      <div style={{ flex: 1 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <div style={{ fontSize: 15, fontWeight: 600 }}>{title}</div>
          {!required && <div style={{ fontSize: 10, fontFamily: MONO, color: SH.muted, padding: '1px 6px', background: SH.bg, borderRadius: 4 }}>OPTIONAL</div>}
        </div>
        <div style={{ fontSize: 13, color: SH.muted, lineHeight: 1.4, marginTop: 2 }}>{body}</div>
      </div>
    </div>
  );

  return (
    <Phone>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '0 24px' }}>
        <div style={{ marginTop: 18, padding: '0 4px' }}>
          <h1 style={{ fontSize: 28, fontWeight: 700, letterSpacing: -0.7, lineHeight: 1.15, margin: 0 }}>
            A few permissions —<br/>here's exactly why.
          </h1>
          <p style={{ fontSize: 14, lineHeight: 1.45, color: SH.muted, marginTop: 10, marginBottom: 0 }}>
            iOS will ask separately. We're explaining first so you can decide with the full picture.
          </p>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 22 }}>
          <PermRow
            icon={Icon.scan(SH.primary, 22)}
            title="Camera"
            body="To scan documents. We don't record video — only the frames you capture."
            required
          />
          <PermRow
            icon={Icon.photos(SH.primary, 20)}
            title="Photo Library"
            body="Only when you tap Import. We never browse on our own."
          />
          <PermRow
            icon={<svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M6 9a6 6 0 1112 0v4l1.5 3h-15L6 13V9z" stroke={SH.primary} strokeWidth="1.6" strokeLinejoin="round"/><path d="M10 19a2 2 0 004 0" stroke={SH.primary} strokeWidth="1.6"/></svg>}
            title="Notifications"
            body="Optional — alerts when a long scan finishes. Nothing else."
          />
        </div>

        <div style={{
          marginTop: 18, padding: 14,
          background: 'rgba(116,198,157,0.12)',
          border: `1px solid ${SH.accentSoft}`,
          borderRadius: 12, display: 'flex', gap: 10,
        }}>
          {Icon.lock(SH.primary, 18)}
          <div style={{ fontSize: 12.5, color: SH.primary, lineHeight: 1.45 }}>
            All processing happens on your device. We never see, upload, or analyze your documents.
          </div>
        </div>

        <div style={{ marginTop: 'auto', marginBottom: 14 }}>
          <div style={{ display: 'flex', gap: 6, justifyContent: 'center', marginBottom: 14 }}>
            <Dot /><Dot /><Dot active />
          </div>
          <Btn variant="primary">Allow & Continue</Btn>
          <div style={{ textAlign: 'center', fontSize: 14, color: SH.muted, marginTop: 14 }}>Maybe Later</div>
        </div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 2 — HOME / LIBRARY
// ─────────────────────────────────────────────────────────────
function ScreenHome() {
  const docs = [
    { name: 'Lease_Agreement_2026', date: 'Apr 14', pages: 8, size: '2.4 MB' },
    { name: 'Receipt_Apothecary', date: 'Apr 12', pages: 1, size: '180 KB' },
    { name: 'Tax_Forms_Q1', date: 'Apr 9', pages: 12, size: '4.1 MB' },
    { name: 'Passport_Scan', date: 'Mar 28', pages: 2, size: '720 KB' },
  ];
  return (
    <Phone>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
        {/* Header */}
        <div style={{ padding: '6px 20px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ width: 22, height: 22, borderRadius: 6, background: SH.primary, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {Icon.check('#74C69D', 13)}
            </div>
            <div style={{ fontSize: 19, fontWeight: 700, letterSpacing: -0.4 }}>ScanHonest</div>
          </div>
          <div style={{ display: 'flex', gap: 14 }}>
            {Icon.search(SH.text, 20)}
            {Icon.gear(SH.text, 20)}
          </div>
        </div>

        {/* Scan counter banner — THE differentiator */}
        <div style={{ padding: '14px 20px 0' }}>
          <div style={{
            background: SH.surface, borderRadius: 14, padding: '12px 14px',
            border: `1px solid ${SH.hairline}`,
            boxShadow: '0 1px 2px rgba(20,30,25,0.04)',
          }}>
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
              <div>
                <div style={{ fontSize: 13, fontWeight: 600, color: SH.text }}>
                  <span style={{ fontFamily: MONO, color: SH.warn }}>3</span>
                  <span style={{ color: SH.muted, fontWeight: 500 }}> of </span>
                  <span style={{ fontFamily: MONO }}>5</span>
                  <span style={{ color: SH.muted, fontWeight: 500 }}> free scans used</span>
                </div>
                <div style={{ fontSize: 11.5, color: SH.muted, marginTop: 2 }}>
                  2 remaining · resets <span style={{ fontFamily: MONO }}>May 1</span>
                </div>
              </div>
              <div style={{ fontSize: 12, color: SH.primary, fontWeight: 600 }}>Upgrade →</div>
            </div>
            {/* progress */}
            <div style={{ height: 5, background: 'rgba(60,60,67,0.08)', borderRadius: 999, marginTop: 9, overflow: 'hidden', display: 'flex' }}>
              <div style={{ width: '20%', background: SH.accent }} />
              <div style={{ width: '20%', background: SH.accent }} />
              <div style={{ width: '20%', background: SH.warn }} />
            </div>
          </div>
        </div>

        {/* Quick actions */}
        <div style={{ padding: '14px 20px 0', display: 'flex', gap: 10 }}>
          <div style={{ flex: 2 }}>
            <Btn variant="primary" icon={Icon.scan('#fff', 20)}>Scan Document</Btn>
          </div>
          <div style={{ flex: 1 }}>
            <Btn variant="ghost" icon={Icon.photos(SH.primary, 18)}><span style={{ fontSize: 13 }}>Import</span></Btn>
          </div>
        </div>

        {/* Recents header */}
        <div style={{ padding: '22px 20px 10px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <div style={{ fontSize: 13, fontWeight: 600, color: SH.muted, textTransform: 'uppercase', letterSpacing: 0.5 }}>Recent</div>
          <div style={{ fontSize: 13, color: SH.primary, fontWeight: 500 }}>All folders</div>
        </div>

        {/* Grid */}
        <div style={{ padding: '0 20px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, flex: 1, overflowY: 'auto' }}>
          {docs.map((d, i) => (
            <div key={i}>
              <DocThumb pages={d.pages} style={{ aspectRatio: '4/5' }} />
              <div style={{ marginTop: 8, fontSize: 13, fontWeight: 500, lineHeight: 1.3, letterSpacing: -0.1, color: SH.text, textOverflow: 'ellipsis', whiteSpace: 'nowrap', overflow: 'hidden' }}>{d.name}</div>
              <div style={{ fontSize: 11, color: SH.muted, fontFamily: MONO, marginTop: 2 }}>{d.date} · {d.pages}p · {d.size}</div>
            </div>
          ))}
        </div>

        {/* Tab bar substitute / no — left swipe folder hint */}
        <div style={{ padding: '6px 20px 4px', textAlign: 'center', fontSize: 11, color: SH.muted, fontFamily: MONO, opacity: 0.7 }}>
          ← swipe for folders
        </div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 3 — CAMERA
// ─────────────────────────────────────────────────────────────
function ScreenCamera() {
  return (
    <Phone dark bg="#0a0a0a">
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, #1a1410 0%, #0d0c0a 50%, #1a1410 100%)' }}>
        {/* simulated camera feed — paper on dark surface */}
        <div style={{ position: 'absolute', top: '18%', left: '10%', right: '10%', bottom: '24%', background: '#fafaf6', borderRadius: 4, transform: 'rotate(-1.5deg)', boxShadow: '0 12px 40px rgba(0,0,0,0.6)' }}>
          <div style={{ padding: '14% 12%', display: 'flex', flexDirection: 'column', gap: 6 }}>
            <div style={{ height: 8, width: '60%', background: SH.primary, borderRadius: 1 }} />
            <div style={{ height: 4 }} />
            <div style={{ height: 4, width: '40%', background: '#888' }} />
            <div style={{ height: 8 }} />
            {[0,1,2,3,4,5,6,7].map(i => <div key={i} style={{ height: 3, background: 'rgba(60,60,67,0.5)', width: `${90 - (i%3)*8}%` }} />)}
            <div style={{ height: 8 }} />
            {[0,1,2,3,4].map(i => <div key={i} style={{ height: 3, background: 'rgba(60,60,67,0.5)', width: `${88 - i*5}%` }} />)}
            <div style={{ height: 8 }} />
            <div style={{ height: 5, width: '38%', background: SH.primary, borderRadius: 1 }} />
          </div>
        </div>

        {/* corner brackets — animated, green = locked */}
        {[
          { top: '17%', left: '9%', tx: 0, ty: 0, rot: 0 },
          { top: '17%', right: '9%', tx: 0, ty: 0, rot: 90 },
          { bottom: '23%', right: '9%', rot: 180 },
          { bottom: '23%', left: '9%', rot: 270 },
        ].map((p, i) => (
          <div key={i} style={{
            position: 'absolute', ...p, width: 28, height: 28,
            borderTop: `3px solid ${SH.accent}`, borderLeft: `3px solid ${SH.accent}`,
            borderTopLeftRadius: 4, transform: `rotate(${p.rot}deg)`,
            boxShadow: `0 0 20px ${SH.accent}80`,
          }} />
        ))}

        {/* Top translucent bar */}
        <div style={{
          position: 'absolute', top: 54, left: 16, right: 16, height: 44,
          borderRadius: 22, padding: '0 14px',
          background: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(20px)',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        }}>
          {Icon.close('#fff', 20)}
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: '#fff', fontSize: 13, fontWeight: 500 }}>
            {Icon.flash('#fff', 18)}
            <span style={{ fontFamily: MONO, fontSize: 11, opacity: 0.7 }}>AUTO</span>
          </div>
          <div style={{ color: '#fff', fontSize: 13, fontWeight: 600, fontFamily: MONO }}>Page 1</div>
        </div>

        {/* Guidance pill */}
        <div style={{
          position: 'absolute', bottom: 200, left: '50%', transform: 'translateX(-50%)',
          padding: '8px 16px', borderRadius: 999,
          background: 'rgba(116,198,157,0.95)', color: SH.primary,
          fontSize: 13, fontWeight: 600, display: 'flex', alignItems: 'center', gap: 6,
          boxShadow: `0 4px 24px ${SH.accent}40`,
        }}>
          {Icon.check(SH.primary, 14)} Document detected
        </div>

        {/* Bottom action bar */}
        <div style={{
          position: 'absolute', bottom: 24, left: 0, right: 0, height: 110,
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '0 28px',
        }}>
          {/* last thumb */}
          <div style={{ position: 'relative', width: 52, height: 60, borderRadius: 7, background: '#fff', boxShadow: '0 4px 12px rgba(0,0,0,0.5)' }}>
            <div style={{ position: 'absolute', top: 5, left: 5, right: 5, bottom: 5, display: 'flex', flexDirection: 'column', gap: 3 }}>
              <div style={{ height: 3, width: '70%', background: SH.primary }} />
              {[0,1,2,3,4].map(i => <div key={i} style={{ height: 1.5, background: '#aaa', width: `${85 - i*5}%` }} />)}
            </div>
          </div>

          {/* shutter */}
          <div style={{ position: 'relative', width: 76, height: 76 }}>
            <div style={{
              position: 'absolute', inset: 0, borderRadius: 999,
              border: '4px solid #fff',
            }} />
            <div style={{
              position: 'absolute', inset: 6, borderRadius: 999,
              background: SH.accent,
              boxShadow: `0 0 20px ${SH.accent}80`,
            }} />
          </div>

          {/* done */}
          <div style={{
            padding: '10px 18px', borderRadius: 999,
            background: 'rgba(255,255,255,0.92)', color: SH.primary,
            fontSize: 14, fontWeight: 700,
          }}>Done</div>
        </div>

        <Anno style={{ top: 110, left: 16, color: 'rgba(255,255,255,0.4)' }}>// brackets pulse 1.6s · spring on lock</Anno>
        <Anno style={{ bottom: 145, right: 16, color: 'rgba(255,255,255,0.4)' }}>// shutter: scale 0.92 · haptic medium</Anno>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 4 — REVIEW & EDIT
// ─────────────────────────────────────────────────────────────
function ScreenReview() {
  const tools = [
    { name: 'Crop', icon: Icon.crop(SH.text, 22) },
    { name: 'Rotate', icon: Icon.rotate(SH.text, 22) },
    { name: 'Enhance', icon: Icon.enhance(SH.primary, 22), active: true },
    { name: 'Filter', icon: Icon.filter(SH.text, 22) },
    { name: 'Retake', icon: Icon.retake(SH.text, 22) },
  ];
  return (
    <Phone>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
        {/* Top bar */}
        <div style={{ padding: '6px 20px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: SH.primary, fontSize: 15, fontWeight: 500 }}>
            {Icon.back(SH.primary, 18)}<span>Retake</span>
          </div>
          <div style={{ fontSize: 16, fontWeight: 600 }}>Review</div>
          <div style={{ padding: '6px 14px', borderRadius: 999, background: SH.primary, color: '#fff', fontSize: 14, fontWeight: 600 }}>Save</div>
        </div>

        {/* Main scan preview */}
        <div style={{ flex: 1, padding: '14px 24px', display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative' }}>
          <div style={{
            width: '100%', aspectRatio: '3/4', background: '#fff', borderRadius: 8,
            boxShadow: '0 4px 16px rgba(20,30,25,0.1), 0 1px 3px rgba(20,30,25,0.06)',
            border: `1px solid ${SH.hairline}`, position: 'relative',
            padding: '10% 9%',
          }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
              <div style={{ height: 9, width: '55%', background: SH.primary }} />
              <div style={{ height: 4 }} />
              <div style={{ height: 4, width: '38%', background: '#999' }} />
              <div style={{ height: 8 }} />
              {[0,1,2,3,4,5,6,7,8].map(i => <div key={i} style={{ height: 3, background: '#bbb', width: `${92 - (i%4)*5}%` }} />)}
              <div style={{ height: 8 }} />
              {[0,1,2,3,4,5].map(i => <div key={i} style={{ height: 3, background: '#bbb', width: `${88 - i*4}%` }} />)}
              <div style={{ height: 10 }} />
              <div style={{ height: 5, width: '40%', background: SH.primary }} />
            </div>
          </div>

          {/* page indicator */}
          <div style={{
            position: 'absolute', top: 26, right: 32,
            padding: '4px 10px', borderRadius: 999,
            background: 'rgba(255,255,255,0.92)', boxShadow: '0 2px 6px rgba(0,0,0,0.08)',
            fontSize: 11, fontFamily: MONO, color: SH.text, fontWeight: 600,
          }}>2 / 3</div>
        </div>

        {/* Page strip */}
        <div style={{ padding: '0 20px 0', display: 'flex', gap: 8, overflowX: 'auto' }}>
          {[1,2,3].map(p => (
            <div key={p} style={{
              width: 52, height: 64, borderRadius: 6, background: '#fff', flexShrink: 0,
              border: p === 2 ? `2px solid ${SH.accent}` : `1px solid ${SH.hairline}`,
              padding: 4, display: 'flex', flexDirection: 'column', gap: 2, position: 'relative',
            }}>
              <div style={{ height: 2.5, background: SH.primary, width: '60%' }} />
              {[0,1,2,3].map(i => <div key={i} style={{ height: 1.5, background: '#bbb', width: `${85 - i*8}%` }} />)}
              <div style={{ position: 'absolute', bottom: 3, right: 3, fontSize: 8, fontFamily: MONO, color: SH.muted }}>{p}</div>
            </div>
          ))}
          <div style={{
            width: 52, height: 64, borderRadius: 6, border: `1.5px dashed ${SH.muted}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>{Icon.plus(SH.muted, 18)}</div>
        </div>

        {/* Toolbar */}
        <div style={{
          margin: '14px 16px 8px', padding: '12px 4px',
          background: SH.surface, borderRadius: 18,
          border: `1px solid ${SH.hairline}`,
          display: 'flex', justifyContent: 'space-around',
          boxShadow: '0 2px 8px rgba(20,30,25,0.04)',
        }}>
          {tools.map(t => (
            <div key={t.name} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, minWidth: 56 }}>
              <div style={{
                width: 38, height: 38, borderRadius: 11,
                background: t.active ? SH.accentSoft : 'transparent',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>{t.icon}</div>
              <div style={{ fontSize: 11, color: t.active ? SH.primary : SH.muted, fontWeight: t.active ? 600 : 500 }}>{t.name}</div>
            </div>
          ))}
        </div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 5 — DOCUMENT DETAIL
// ─────────────────────────────────────────────────────────────
function ScreenDocDetail() {
  const Action = ({ icon, label, pro }) => (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, position: 'relative', flex: 1 }}>
      <div style={{ height: 28, display: 'flex', alignItems: 'center' }}>{icon}</div>
      <div style={{ fontSize: 10.5, color: SH.muted, fontWeight: 500 }}>{label}</div>
      {pro && (
        <div style={{ position: 'absolute', top: -2, right: 8, padding: '1px 5px', background: SH.gold, color: '#fff', borderRadius: 3, fontSize: 8, fontFamily: MONO, fontWeight: 700, letterSpacing: 0.4 }}>PRO</div>
      )}
    </div>
  );

  return (
    <Phone>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
        {/* nav */}
        <div style={{ padding: '6px 16px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: SH.primary, fontSize: 15 }}>
            {Icon.back(SH.primary, 18)}<span>Library</span>
          </div>
          <div style={{ fontSize: 14, fontWeight: 600, maxWidth: 180, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>Lease_Agreement_2026</div>
          {Icon.more(SH.text, 22)}
        </div>

        {/* viewer */}
        <div style={{ flex: 1, overflow: 'hidden', padding: '14px 20px 0', position: 'relative' }}>
          <div style={{
            width: '100%', height: '100%', background: '#fff', borderRadius: 8,
            boxShadow: '0 1px 3px rgba(0,0,0,0.06), 0 8px 24px rgba(0,0,0,0.06)',
            border: `1px solid ${SH.hairline}`, padding: '8% 8% 0',
            overflow: 'hidden',
          }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              <div style={{ height: 11, width: '70%', background: SH.primary }} />
              <div style={{ height: 4, width: '40%', background: '#888', marginTop: 2 }} />
              <div style={{ height: 10 }} />
              <div style={{ height: 4, width: '30%', background: SH.text }} />
              <div style={{ height: 5 }} />
              {[0,1,2,3,4,5,6,7,8,9,10].map(i => <div key={i} style={{ height: 3, background: '#bbb', width: `${94 - (i%5)*4}%` }} />)}
              <div style={{ height: 8 }} />
              <div style={{ height: 4, width: '28%', background: SH.text }} />
              <div style={{ height: 5 }} />
              {[0,1,2,3,4,5,6,7].map(i => <div key={i} style={{ height: 3, background: '#bbb', width: `${90 - (i%4)*5}%` }} />)}
            </div>
          </div>

          {/* page pill */}
          <div style={{
            position: 'absolute', bottom: 16, left: '50%', transform: 'translateX(-50%)',
            padding: '5px 12px', borderRadius: 999, background: 'rgba(0,0,0,0.7)', color: '#fff',
            fontSize: 11, fontFamily: MONO, fontWeight: 600,
          }}>Page 1 / 8</div>
        </div>

        {/* Bottom actions */}
        <div style={{
          margin: '10px 16px 12px', padding: '14px 8px',
          background: SH.surface, borderRadius: 20,
          border: `1px solid ${SH.hairline}`,
          display: 'flex', boxShadow: '0 2px 8px rgba(20,30,25,0.05)',
        }}>
          <Action icon={Icon.share(SH.primary, 22)} label="Share" />
          <Action icon={Icon.pdf(SH.primary, 22)} label="Export" />
          <Action icon={Icon.text(SH.primary, 22)} label="OCR" pro />
          <Action icon={Icon.lock(SH.primary, 22)} label="Lock" pro />
          <Action icon={Icon.more(SH.primary, 22)} label="More" />
        </div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 6 — PAYWALL (the anti-iScanner)
// ─────────────────────────────────────────────────────────────
function ScreenPaywall() {
  const features = [
    'Unlimited scans',
    'iCloud sync across all devices',
    'OCR — search inside documents',
    'Folder organization',
    'AI smart file naming',
    'iOS home screen widget',
    'Password protection',
    'Google Drive & Dropbox export',
  ];
  return (
    <Phone>
      <div style={{ height: '100%', overflowY: 'auto', padding: '0 20px' }}>
        {/* Close — iOS-system-style: filled gray circle */}
        <div style={{ display: 'flex', justifyContent: 'flex-end', paddingTop: 8 }}>
          <div style={{
            width: 30, height: 30, borderRadius: 999,
            background: 'rgba(120,120,128,0.18)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'pointer',
          }}>{Icon.close(SH.muted, 13)}</div>
        </div>

        {/* Header */}
        <div style={{ marginTop: 8 }}>
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 6, padding: '5px 10px',
            background: SH.accentSoft, borderRadius: 999,
            fontSize: 11, fontFamily: MONO, color: SH.primary, fontWeight: 600, letterSpacing: 0.4,
          }}>
            {Icon.text(SH.primary, 12)} OCR REQUIRES PRO
          </div>
          <h1 style={{ fontSize: 30, fontWeight: 700, letterSpacing: -0.7, lineHeight: 1.1, marginTop: 12, marginBottom: 4 }}>
            Upgrade to Pro
          </h1>
          <p style={{ fontSize: 14.5, color: SH.muted, lineHeight: 1.4, margin: 0 }}>
            One honest price. All features. No tricks.
          </p>
        </div>

        {/* Limit context — scan usage card */}
        <div style={{
          marginTop: 14, padding: '12px 14px', borderRadius: 12,
          background: SH.bg, border: `1px solid rgba(220,53,69,0.2)`,
          fontSize: 13, color: SH.text, lineHeight: 1.4,
        }}>
          {/* Row: label + count */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 7 }}>
            <span style={{ fontSize: 12.5, color: SH.text, fontWeight: 500 }}>Free scans used this month</span>
            <span style={{ fontFamily: MONO, fontWeight: 700, fontSize: 13, color: SH.danger }}>5 / 5</span>
          </div>
          {/* Progress bar — full = danger red */}
          <div style={{ height: 5, borderRadius: 999, background: 'rgba(220,53,69,0.15)', overflow: 'hidden', marginBottom: 8 }}>
            <div style={{ width: '100%', height: '100%', background: SH.danger, borderRadius: 999 }} />
          </div>
          {/* Reset + upgrade CTA */}
          <div style={{ fontSize: 12, color: SH.muted, lineHeight: 1.5 }}>
            Resets <span style={{ fontFamily: MONO, color: SH.text, fontWeight: 500 }}>May 1, 2026</span>
            {' — or '}
            <span style={{ color: SH.primary, fontWeight: 600 }}>upgrade now</span>
            {' to scan without limits.'}
          </div>
        </div>

        {/* Pricing — equal weight */}
        <div style={{ marginTop: 20, display: 'flex', gap: 10, overflow: 'visible' }}>
          <div style={{
            flex: 1, padding: 14, borderRadius: 16, background: SH.surface,
            border: `2px solid ${SH.primary}`, position: 'relative',
            boxShadow: '0 4px 16px rgba(27,67,50,0.1)',
          }}>
            <div style={{
              position: 'absolute', top: -10, left: 12,
              padding: '3px 8px', background: SH.primary, color: '#fff',
              borderRadius: 999, fontSize: 9, fontFamily: MONO, letterSpacing: 0.5,
            }}>MOST TRUSTED</div>
            <div style={{ fontSize: 11, color: SH.muted, fontFamily: MONO, textTransform: 'uppercase', letterSpacing: 0.5 }}>One-time</div>
            <div style={{ fontSize: 28, fontWeight: 700, letterSpacing: -0.8, marginTop: 4, color: SH.primary }}>$4.99</div>
            <div style={{ fontSize: 12, color: SH.text, fontWeight: 500, marginTop: 4 }}>Yours forever</div>
            <div style={{ fontSize: 11, color: SH.muted, marginTop: 2, lineHeight: 1.3 }}>No recurring charges. Ever.</div>
            <div style={{
              marginTop: 12, height: 38, borderRadius: 19,
              background: SH.primary, color: '#fff',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 13, fontWeight: 600,
            }}>Buy Once</div>
            <div style={{ marginTop: 8, fontSize: 10, color: SH.muted, fontFamily: MONO, textAlign: 'center' }}>73% choose this</div>
          </div>

          <div style={{
            flex: 1, padding: 14, borderRadius: 16, background: SH.surface,
            border: `1.5px solid ${SH.hairline}`,
          }}>
            <div style={{ fontSize: 11, color: SH.muted, fontFamily: MONO, textTransform: 'uppercase', letterSpacing: 0.5 }}>Monthly</div>
            <div style={{ fontSize: 28, fontWeight: 700, letterSpacing: -0.8, marginTop: 4, color: SH.text }}>$1.99</div>
            <div style={{ fontSize: 12, color: SH.text, fontWeight: 500, marginTop: 4 }}>per month</div>
            <div style={{ fontSize: 11, color: SH.muted, marginTop: 2, lineHeight: 1.3 }}>Cancel anytime.<br/>Next: <span style={{ fontFamily: MONO }}>May 29</span></div>
            <div style={{
              marginTop: 12, height: 38, borderRadius: 19,
              background: 'transparent', color: SH.primary,
              border: `1.5px solid ${SH.primary}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 13, fontWeight: 600,
            }}>Try Monthly</div>
            <div style={{ marginTop: 8, fontSize: 10, color: SH.muted, fontFamily: MONO, textAlign: 'center' }}>&nbsp;</div>
          </div>
        </div>

        {/* Features */}
        <div style={{ marginTop: 18, padding: '14px 16px', background: SH.surface, borderRadius: 16, border: `1px solid ${SH.hairline}` }}>
          <div style={{ fontSize: 11, fontFamily: MONO, color: SH.muted, letterSpacing: 0.5, textTransform: 'uppercase', marginBottom: 8 }}>WHAT YOU GET</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
            {features.map(f => (
              <div key={f} style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                {Icon.check(SH.accent, 16)}
                <div style={{ fontSize: 13.5, color: SH.text }}>{f}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Honest footer — 15px, NOT grey footnote */}
        <div style={{ marginTop: 16, fontSize: 14, color: SH.text, lineHeight: 1.5 }}>
          <div><strong>Cancel anytime — no questions asked.</strong></div>
          <div style={{ marginTop: 6, color: SH.primary, fontWeight: 600 }}>Restore previous purchase</div>
          <div style={{ marginTop: 6, color: SH.muted, fontSize: 13 }}>Questions? <span style={{ color: SH.primary, fontWeight: 500 }}>help@scanhonest.com</span></div>
        </div>

        <div style={{ marginTop: 14, marginBottom: 12, fontSize: 11, color: SH.muted, textAlign: 'center' }}>
          Privacy Policy · Terms of Use
        </div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 7 — POST-PURCHASE
// ─────────────────────────────────────────────────────────────
function ScreenPostPurchase() {
  const items = [
    { label: 'Unlimited scans', state: 'active' },
    { label: 'iCloud sync', state: 'enable' },
    { label: 'OCR — search documents', state: 'active' },
    { label: 'Folder organization', state: 'active' },
    { label: 'AI smart naming', state: 'active' },
    { label: 'Home screen widget', state: 'enable' },
  ];
  return (
    <Phone>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '0 24px' }}>
        {/* big check */}
        <div style={{ marginTop: 28, display: 'flex', justifyContent: 'center' }}>
          <div style={{
            width: 84, height: 84, borderRadius: 999,
            background: SH.accentSoft, display: 'flex', alignItems: 'center', justifyContent: 'center',
            position: 'relative',
          }}>
            <div style={{
              position: 'absolute', inset: -8, borderRadius: 999,
              border: `1.5px dashed ${SH.accent}`, opacity: 0.6,
            }} />
            {Icon.check(SH.primary, 44)}
          </div>
        </div>

        <h1 style={{ fontSize: 30, fontWeight: 700, letterSpacing: -0.7, textAlign: 'center', margin: '20px 0 6px' }}>
          You're Pro. Thank you.
        </h1>

        {/* Receipt block */}
        <div style={{
          marginTop: 14, padding: 14, borderRadius: 14,
          background: SH.surface, border: `1px solid ${SH.hairline}`,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: SH.muted, fontFamily: MONO, textTransform: 'uppercase', letterSpacing: 0.5 }}>
            <span>Receipt</span>
            <span>#SH-9341</span>
          </div>
          <div style={{ marginTop: 8, fontSize: 15, fontWeight: 600, color: SH.text }}>Lifetime access · One-time</div>
          <div style={{ marginTop: 4, fontSize: 13, color: SH.muted, fontFamily: MONO }}>$4.99 · Paid Apr 29, 2026</div>
          <div style={{ marginTop: 10, paddingTop: 10, borderTop: `1px solid ${SH.hairline}`, fontSize: 12, color: SH.muted }}>
            Receipt sent to <span style={{ color: SH.text, fontWeight: 500 }}>jordan@example.com</span>
          </div>
        </div>

        {/* Unlocked checklist */}
        <div style={{ marginTop: 16, flex: 1, overflowY: 'auto' }}>
          <div style={{ fontSize: 11, fontFamily: MONO, color: SH.muted, letterSpacing: 0.5, textTransform: 'uppercase', marginBottom: 8 }}>UNLOCKED NOW</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
            {items.map((it, i) => (
              <div key={i} style={{
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '10px 12px', background: SH.surface,
                borderRadius: 12, border: `1px solid ${SH.hairline}`,
              }}>
                <div style={{
                  width: 22, height: 22, borderRadius: 999,
                  background: it.state === 'active' ? SH.accent : SH.bg,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  border: it.state === 'active' ? 'none' : `1px solid ${SH.hairline}`,
                }}>
                  {it.state === 'active' && Icon.check('#fff', 14)}
                </div>
                <div style={{ flex: 1, fontSize: 14, color: SH.text, fontWeight: 500 }}>{it.label}</div>
                <div style={{
                  fontSize: 11, fontFamily: MONO, fontWeight: 600,
                  color: it.state === 'active' ? SH.primary : SH.gold,
                  letterSpacing: 0.5,
                }}>{it.state === 'active' ? 'ACTIVE' : 'TAP TO ENABLE'}</div>
              </div>
            ))}
          </div>
          <Anno style={{ position: 'static', marginTop: 10, color: SH.muted }}>// each row slides in · 80ms stagger</Anno>
        </div>

        <div style={{ marginTop: 8 }}>
          <Btn variant="primary">Continue Scanning</Btn>
          <div style={{ textAlign: 'center', fontSize: 13, color: SH.primary, marginTop: 12, marginBottom: 8, fontWeight: 500 }}>
            Manage subscription
          </div>
        </div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 8 — SETTINGS
// ─────────────────────────────────────────────────────────────
function ScreenSettings() {
  const Group = ({ title, children }) => (
    <>
      <div style={{ padding: '18px 20px 6px', fontSize: 11, fontFamily: MONO, color: SH.muted, letterSpacing: 0.5, textTransform: 'uppercase' }}>{title}</div>
      <div style={{ margin: '0 16px', borderRadius: 14, background: SH.surface, border: `1px solid ${SH.hairline}`, overflow: 'hidden' }}>{children}</div>
    </>
  );
  const Row = ({ left, right, sub, last }) => (
    <div style={{ padding: '12px 14px', borderBottom: last ? 'none' : `1px solid ${SH.hairline}`, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
      <div>
        <div style={{ fontSize: 14, color: SH.text }}>{left}</div>
        {sub && <div style={{ fontSize: 11, color: SH.muted, marginTop: 2, fontFamily: MONO }}>{sub}</div>}
      </div>
      <div style={{ fontSize: 13, color: SH.muted, display: 'flex', alignItems: 'center', gap: 4 }}>{right}</div>
    </div>
  );
  const Toggle = ({ on }) => (
    <div style={{ width: 44, height: 26, borderRadius: 999, background: on ? SH.accent : 'rgba(60,60,67,0.16)', position: 'relative', transition: 'all .2s' }}>
      <div style={{ position: 'absolute', top: 2, left: on ? 20 : 2, width: 22, height: 22, borderRadius: 999, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.15)', transition: 'all .2s' }} />
    </div>
  );

  return (
    <Phone>
      <div style={{ height: '100%', overflowY: 'auto' }}>
        <div style={{ padding: '6px 20px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: -0.5 }}>Settings</div>
          <div style={{ fontSize: 14, color: SH.primary, fontWeight: 500 }}>Done</div>
        </div>

        {/* Pro card */}
        <div style={{ margin: '16px 16px 0', padding: 16, borderRadius: 16, background: 'linear-gradient(135deg, #1B4332 0%, #2D6A4F 100%)', color: '#fff', position: 'relative', overflow: 'hidden' }}>
          <div style={{ position: 'absolute', top: -20, right: -20, width: 100, height: 100, borderRadius: 999, background: 'rgba(116,198,157,0.15)' }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10, fontFamily: MONO, letterSpacing: 1, textTransform: 'uppercase', opacity: 0.7 }}>
            <div style={{ width: 14, height: 14, borderRadius: 4, background: SH.gold, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 9, color: '#fff', fontWeight: 700 }}>★</div>
            ScanHonest Pro
          </div>
          <div style={{ marginTop: 8, fontSize: 22, fontWeight: 700, letterSpacing: -0.5 }}>Lifetime · Unlimited</div>
          <div style={{ marginTop: 4, fontSize: 12, opacity: 0.75, fontFamily: MONO }}>Purchased Apr 29, 2026 · $4.99</div>
        </div>

        <Group title="Account">
          <Row left="Manage Subscription" right="↗" />
          <Row left="Restore Purchase" right="" />
          <Row left="Sign in with Apple" sub="for iCloud identity" right="Connected" last />
        </Group>

        <Group title="Scanning">
          <Row left="Default format" right="PDF ›" />
          <Row left="Auto-enhance" right={<Toggle on />} />
          <Row left="Auto-capture" sub="Sensitivity: high" right={<Toggle on />} />
          <Row left="Default folder" right="All Documents ›" last />
        </Group>

        <Group title="Storage">
          <Row left="iCloud Sync" sub="On · 47 MB · 128 scans" right={<Toggle on />} />
          <Row left="Free Up Space" sub="delete scans older than 1y" right="›" last />
        </Group>

        <Group title="Privacy">
          <Row left="All processing on-device" sub="we never see your scans" right={Icon.check(SH.accent, 16)} />
          <Row left="Face ID lock" right={<Toggle on={false} />} last />
        </Group>

        <Group title="Support">
          <Row left="Send Feedback" right="›" />
          <Row left="What's New" sub="v2.4.1" right="›" />
          <Row left="help@scanhonest.com" right="›" last />
        </Group>

        <div style={{ padding: '20px 20px 30px', textAlign: 'center', fontSize: 11, color: SH.muted, fontFamily: MONO }}>
          ScanHonest 2.4.1 · build 412
        </div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 9 — WIDGETS (3 sizes, on a faux home screen)
// ─────────────────────────────────────────────────────────────
function ScreenWidgets() {
  const wallpaperBg = 'linear-gradient(160deg, #2d4a3a 0%, #1a2e25 50%, #0e1a14 100%)';
  // small (2x2)
  const Small = () => (
    <div style={{
      width: 138, height: 138, borderRadius: 22, background: SH.surface, padding: 14,
      display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
      boxShadow: '0 6px 16px rgba(0,0,0,0.18)',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <div style={{ width: 18, height: 18, borderRadius: 5, background: SH.primary, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{Icon.check('#74C69D', 11)}</div>
        <div style={{ fontSize: 11, fontWeight: 600, color: SH.text }}>ScanHonest</div>
      </div>
      <div style={{
        background: SH.primary, borderRadius: 14, padding: '14px 0',
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, color: '#fff',
      }}>
        {Icon.scan('#fff', 28)}
        <div style={{ fontSize: 13, fontWeight: 600 }}>Scan</div>
      </div>
    </div>
  );

  // medium (4x2)
  const Medium = () => (
    <div style={{
      width: 296, height: 138, borderRadius: 22, background: SH.surface, padding: 14,
      display: 'flex', gap: 12,
      boxShadow: '0 6px 16px rgba(0,0,0,0.18)',
    }}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <div style={{ width: 16, height: 16, borderRadius: 4, background: SH.primary, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{Icon.check('#74C69D', 10)}</div>
          <div style={{ fontSize: 10, fontWeight: 600 }}>ScanHonest</div>
        </div>
        <div style={{
          marginTop: 8, flex: 1, background: SH.primary, borderRadius: 12,
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, color: '#fff',
        }}>
          {Icon.scan('#fff', 24)}
          <div style={{ fontSize: 12, fontWeight: 600 }}>Scan</div>
        </div>
        <div style={{ marginTop: 6, fontSize: 9, color: SH.muted, fontFamily: MONO, textAlign: 'center' }}>3 / 5 free</div>
      </div>
      <div style={{ flex: 1.4, display: 'flex', flexDirection: 'column', gap: 6 }}>
        <div style={{ fontSize: 9, color: SH.muted, fontFamily: MONO, letterSpacing: 0.4, textTransform: 'uppercase' }}>RECENT</div>
        {[
          { name: 'Lease_2026', meta: '8p · today' },
          { name: 'Receipt_Apo', meta: '1p · 2d ago' },
        ].map((d, i) => (
          <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center', padding: '4px 0', borderBottom: i === 0 ? `1px solid ${SH.hairline}` : 'none' }}>
            <DocThumb pages={1} style={{ width: 28, height: 36 }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 11, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{d.name}</div>
              <div style={{ fontSize: 9, color: SH.muted, fontFamily: MONO }}>{d.meta}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );

  // large (4x4)
  const Large = () => (
    <div style={{
      width: 296, height: 296, borderRadius: 22, background: SH.surface, padding: 16,
      display: 'flex', flexDirection: 'column',
      boxShadow: '0 6px 16px rgba(0,0,0,0.18)',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <div style={{ width: 18, height: 18, borderRadius: 5, background: SH.primary, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{Icon.check('#74C69D', 11)}</div>
          <div style={{ fontSize: 11, fontWeight: 600 }}>ScanHonest</div>
        </div>
        <div style={{ fontSize: 9, color: SH.gold, fontFamily: MONO, fontWeight: 700, letterSpacing: 0.4 }}>PRO ∞</div>
      </div>
      <div style={{ marginTop: 12, fontSize: 9, color: SH.muted, fontFamily: MONO, letterSpacing: 0.4, textTransform: 'uppercase' }}>RECENT 4</div>
      <div style={{ marginTop: 8, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, flex: 1 }}>
        {['Lease_2026', 'Receipt_Apo', 'Tax_Q1', 'Passport'].map((n, i) => (
          <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <DocThumb pages={[8,1,12,2][i]} style={{ flex: 1 }} />
            <div style={{ fontSize: 9, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{n}</div>
          </div>
        ))}
      </div>
      <div style={{
        marginTop: 10, height: 32, borderRadius: 12,
        background: SH.primary, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
        fontSize: 12, fontWeight: 600,
      }}>
        {Icon.scan('#fff', 16)} Scan now
      </div>
    </div>
  );

  return (
    <Phone bg="#000">
      <div style={{ position: 'absolute', inset: 0, background: wallpaperBg }}>
        <div style={{ padding: '14px 20px 0', textAlign: 'center', color: '#fff' }}>
          <div style={{ fontSize: 76, fontWeight: 200, letterSpacing: -2, lineHeight: 1, fontFamily: FONT }}>9:41</div>
          <div style={{ fontSize: 15, opacity: 0.85, marginTop: 2 }}>Wednesday, April 29</div>
        </div>

        <div style={{ padding: '24px 20px 0', display: 'flex', flexDirection: 'column', gap: 16, alignItems: 'center' }}>
          <div style={{ display: 'flex', gap: 16, width: '100%', justifyContent: 'center' }}>
            <Small />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div style={{ fontSize: 10, fontFamily: MONO, color: 'rgba(255,255,255,0.6)', letterSpacing: 0.5 }}>SMALL · 2×2</div>
              <div style={{ fontSize: 10, fontFamily: MONO, color: 'rgba(255,255,255,0.4)', letterSpacing: 0.3, lineHeight: 1.5 }}>tap → camera<br/>direct, no menus</div>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, alignItems: 'flex-start' }}>
            <div style={{ fontSize: 10, fontFamily: MONO, color: 'rgba(255,255,255,0.6)', letterSpacing: 0.5 }}>MEDIUM · 4×2</div>
            <Medium />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, alignItems: 'flex-start' }}>
            <div style={{ fontSize: 10, fontFamily: MONO, color: 'rgba(255,255,255,0.6)', letterSpacing: 0.5 }}>LARGE · 4×4 — PRO</div>
            <Large />
          </div>
        </div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────
// SCREEN 10B — Native handoff
// Format picker + Password Protect → hands off to iOS share sheet
// ─────────────────────────────────────────────────────────────
function ScreenShareV2() {
  const fmt = (label, sub, active, pro) => (
    <div style={{
      flex: 1, padding: '10px 8px', borderRadius: 12, position: 'relative',
      background: active ? SH.accentSoft : SH.bg,
      border: active ? `1.5px solid ${SH.accent}` : `1px solid ${SH.hairline}`,
      textAlign: 'center',
    }}>
      <div style={{ fontSize: 12.5, fontWeight: 600, color: SH.text }}>{label}</div>
      <div style={{ fontSize: 10, color: SH.muted, marginTop: 1, fontFamily: MONO }}>{sub}</div>
      {pro && <div style={{ position: 'absolute', top: 4, right: 4, fontSize: 8, fontFamily: MONO, color: SH.gold, fontWeight: 700, letterSpacing: 0.4 }}>PRO</div>}
    </div>
  );

  const nativeIcon = (name, bg, glyph) => (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, flex: 1, minWidth: 0 }}>
      <div style={{
        width: 52, height: 52, borderRadius: 12, background: bg,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 18, color: '#fff', boxShadow: '0 1px 4px rgba(0,0,0,0.12)',
      }}>{glyph}</div>
      <div style={{ fontSize: 10, color: SH.text, textAlign: 'center', lineHeight: 1.2 }}>{name}</div>
    </div>
  );

  const nativeRow = (icon, label) => (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14, padding: '11px 20px',
      borderBottom: `1px solid rgba(60,60,67,0.06)`, fontSize: 14, color: SH.text,
    }}>
      <div style={{ width: 30, height: 30, borderRadius: 7, background: 'rgba(60,60,67,0.08)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14 }}>{icon}</div>
      {label}
    </div>
  );

  return (
    <Phone>
      {/* dim overlay */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(15,20,17,0.45)', zIndex: 1 }} />

      {/* blurred library bg */}
      <div style={{ position: 'absolute', inset: 0, padding: '14px 20px', filter: 'blur(2px)', opacity: 0.4 }}>
        <div style={{ height: 22, width: 140, background: SH.surface, borderRadius: 6 }} />
        <div style={{ marginTop: 14, height: 60, background: SH.surface, borderRadius: 12 }} />
        <div style={{ marginTop: 14, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          {[0,1,2,3].map(i => <div key={i} style={{ aspectRatio: '4/5', background: SH.surface, borderRadius: 10 }} />)}
        </div>
      </div>

      {/* ── Native iOS share sheet (bottom layer) ── */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 5,
        background: 'rgba(242,242,247,0.96)', backdropFilter: 'blur(20px)',
        borderTopLeftRadius: 16, borderTopRightRadius: 16,
        height: 238, overflow: 'hidden',
        boxShadow: '0 -2px 16px rgba(0,0,0,0.10)',
      }}>
        {/* App icons row */}
        <div style={{ padding: '14px 16px 12px', borderBottom: '1px solid rgba(60,60,67,0.10)' }}>
          <div style={{ fontSize: 10, color: '#6C757D', textAlign: 'center', marginBottom: 10,
            fontFamily: MONO, letterSpacing: 0.3, textTransform: 'uppercase' }}>iOS Share Sheet</div>
          <div style={{ display: 'flex', gap: 0 }}>
            {nativeIcon('AirDrop',  '#0a84ff', '◎')}
            {nativeIcon('Messages', '#34c759', '✉')}
            {nativeIcon('Mail',     '#1c8aff', '@')}
            {nativeIcon('Notes',    '#ffcc00', '✎')}
            {nativeIcon('Files',    '#3a8dff', '📁')}
          </div>
        </div>
        {/* Action rows */}
        {nativeRow('⊕', 'Copy to Clipboard')}
        {nativeRow('↙', 'Save to Files')}
        {nativeRow('🖨', 'Print')}
      </div>

      {/* ── Our prep sheet (top layer — owns format + encryption) ── */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 232, zIndex: 10,
        background: SH.bg, borderTopLeftRadius: 26, borderTopRightRadius: 26,
        padding: '10px 20px 18px',
        boxShadow: '0 -8px 32px rgba(0,0,0,0.16)',
      }}>
        {/* drag handle */}
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 10 }}>
          <div style={{ width: 36, height: 4, borderRadius: 999, background: 'rgba(60,60,67,0.18)' }} />
        </div>

        {/* doc header */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, paddingBottom: 12,
          borderBottom: `1px solid ${SH.hairline}`, marginBottom: 12 }}>
          <DocThumb pages={8} style={{ width: 40, height: 52 }} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14, fontWeight: 600, whiteSpace: 'nowrap',
              overflow: 'hidden', textOverflow: 'ellipsis' }}>Lease_Agreement_2026</div>
            <div style={{ fontSize: 11, color: SH.muted, fontFamily: MONO, marginTop: 2 }}>8 pages · 2.4 MB · PDF</div>
          </div>
          <div style={{ width: 28, height: 28, borderRadius: 999, background: 'rgba(60,60,67,0.08)',
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            {Icon.close(SH.muted, 13)}
          </div>
        </div>

        {/* Format chips */}
        <div style={{ fontSize: 10, fontFamily: MONO, color: SH.muted, letterSpacing: 0.5,
          textTransform: 'uppercase', marginBottom: 7 }}>Format</div>
        <div style={{ display: 'flex', gap: 7, marginBottom: 12 }}>
          {fmt('PDF', 'default', true)}
          {fmt('JPEG', 'images', false)}
          {fmt('TXT', 'OCR text', false, true)}
          {fmt('PDF·sm', 'compact', false)}
        </div>

        {/* Password protect row */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '10px 12px', background: SH.surface, borderRadius: 12,
          border: `1px solid ${SH.hairline}`, marginBottom: 14,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
            {Icon.lock(SH.primary, 15)}
            <div>
              <div style={{ fontSize: 13, fontWeight: 500, color: SH.text }}>Password Protect</div>
              <div style={{ fontSize: 10, color: SH.muted, fontFamily: MONO }}>AES-256 encryption</div>
            </div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
            <div style={{ fontSize: 7.5, fontFamily: MONO, color: SH.gold, fontWeight: 700,
              letterSpacing: 0.3, padding: '2px 5px', background: SH.goldSoft, borderRadius: 3 }}>PRO</div>
            {/* toggle off */}
            <div style={{ width: 42, height: 24, borderRadius: 12, background: 'rgba(60,60,67,0.14)',
              position: 'relative', flexShrink: 0 }}>
              <div style={{ position: 'absolute', left: 2, top: 2, width: 20, height: 20,
                borderRadius: 10, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.2)' }} />
            </div>
          </div>
        </div>

        {/* Primary Share CTA — hands off to native */}
        <div style={{
          height: 50, borderRadius: 25, background: SH.primary,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9,
          color: '#fff', fontSize: 16, fontWeight: 600,
          boxShadow: `0 4px 16px rgba(27,67,50,0.35)`,
        }}>
          {Icon.share('#fff', 17)}
          Share via iOS…
        </div>
        <div style={{ fontSize: 10, color: SH.muted, textAlign: 'center', marginTop: 7,
          fontFamily: MONO, letterSpacing: 0.2 }}>opens iOS share sheet ↓</div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 11B-A — IMPORT CHOICE POPUP
// Bottom sheet: user picks source for import
// ─────────────────────────────────────────────────────────────
function ScreenImportChoicePopup() {
  const Option = ({ icon, title, sub }) => (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14, padding: '14px 16px',
      background: SH.surface, borderRadius: 14,
      border: `1px solid ${SH.hairline}`,
      boxShadow: '0 1px 4px rgba(0,0,0,0.04)',
    }}>
      <div style={{
        width: 44, height: 44, borderRadius: 12, background: SH.accentSoft,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 20, flexShrink: 0,
      }}>{icon}</div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 15, fontWeight: 600, color: SH.text }}>{title}</div>
        <div style={{ fontSize: 12, color: SH.muted, fontFamily: MONO, marginTop: 2 }}>{sub}</div>
      </div>
      <div style={{ fontSize: 18, color: SH.primary, opacity: 0.5 }}>›</div>
    </div>
  );

  return (
    <Phone>
      {/* dim overlay */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.35)', zIndex: 1 }} />
      {/* sheet */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 10,
        background: SH.bg, borderTopLeftRadius: 28, borderTopRightRadius: 28,
        padding: '10px 20px 32px',
      }}>
        {/* drag handle */}
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 18 }}>
          <div style={{ width: 36, height: 4, borderRadius: 999, background: 'rgba(60,60,67,0.18)' }} />
        </div>
        <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: -0.4, marginBottom: 4 }}>Import Document</div>
        <div style={{ fontSize: 13, color: SH.muted, marginBottom: 20 }}>Choose your source</div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <Option icon="🖼" title="Camera Roll" sub="JPEG · HEIC · PNG" />
          <Option icon="📄" title="Files App" sub="PDF · images · any document" />
        </div>

        <div style={{
          marginTop: 16, height: 50, borderRadius: 25,
          background: 'rgba(60,60,67,0.07)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 15, fontWeight: 500, color: SH.muted,
        }}>Cancel</div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 11B-B — PRO OCR POPUP
// Shown when a free user taps OCR — upgrade prompt
// ─────────────────────────────────────────────────────────────
function ScreenOCRProPopup() {
  const Feature = ({ label }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      {Icon.check(SH.accent, 16)}
      <div style={{ fontSize: 14, color: SH.text }}>{label}</div>
    </div>
  );

  return (
    <Phone>
      {/* dim overlay */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.45)', zIndex: 1 }} />
      {/* sheet */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 10,
        background: SH.bg, borderTopLeftRadius: 28, borderTopRightRadius: 28,
        padding: '10px 24px 36px',
      }}>
        {/* drag handle */}
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 20 }}>
          <div style={{ width: 36, height: 4, borderRadius: 999, background: 'rgba(60,60,67,0.18)' }} />
        </div>

        {/* icon + badge */}
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 14, marginBottom: 18 }}>
          <div style={{
            width: 56, height: 56, borderRadius: 16, background: SH.accentSoft,
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            {Icon.text(SH.primary, 28)}
          </div>
          <div style={{ flex: 1 }}>
            <div style={{
              display: 'inline-flex', alignItems: 'center', gap: 5, marginBottom: 6,
              padding: '3px 8px', background: SH.goldSoft, borderRadius: 999,
              fontSize: 10, fontFamily: MONO, color: SH.gold, fontWeight: 700, letterSpacing: 0.5,
            }}>★ PRO FEATURE</div>
            <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: -0.4, color: SH.text, lineHeight: 1.2 }}>
              Extract Text (OCR)
            </div>
            <div style={{ fontSize: 13, color: SH.muted, marginTop: 4, lineHeight: 1.4 }}>
              Search inside your docs, copy text, and export as TXT.
            </div>
          </div>
        </div>

        {/* feature list */}
        <div style={{
          padding: '14px 16px', background: SH.surface, borderRadius: 14,
          border: `1px solid ${SH.hairline}`, marginBottom: 20,
          display: 'flex', flexDirection: 'column', gap: 10,
        }}>
          <Feature label="Search inside any scanned document" />
          <Feature label="Copy & paste extracted text" />
          <Feature label="Export as plain .txt file" />
          <Feature label="Works offline — no cloud needed" />
        </div>

        {/* CTA */}
        <div style={{
          height: 52, borderRadius: 26, background: SH.primary,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 16, fontWeight: 600, color: '#fff',
          boxShadow: '0 4px 16px rgba(27,67,50,0.3)', marginBottom: 12,
        }}>Upgrade to Pro — $4.99</div>

        <div style={{
          textAlign: 'center', fontSize: 14, color: SH.muted, fontWeight: 500,
        }}>Maybe Later</div>
      </div>
    </Phone>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 11C — DELETE DOCUMENT POPUP
// Centered modal confirmation with destructive styling
// ─────────────────────────────────────────────────────────────
function ScreenDeletePopup() {
  return (
    <Phone>
      {/* dim overlay */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.45)', zIndex: 1,
        display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '0 28px' }}>
        <div style={{
          width: '100%', background: SH.surface, borderRadius: 22,
          overflow: 'hidden', boxShadow: '0 16px 48px rgba(0,0,0,0.22)',
        }}>
          {/* top section */}
          <div style={{ padding: '28px 24px 20px', textAlign: 'center' }}>
            {/* trash icon in red circle */}
            <div style={{
              width: 60, height: 60, borderRadius: 999,
              background: 'rgba(220,53,69,0.1)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              margin: '0 auto 16px',
            }}>
              <svg width="26" height="26" viewBox="0 0 24 24" fill="none">
                <path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6" stroke="#DC3545" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
                <path d="M10 11v5M14 11v5" stroke="#DC3545" strokeWidth="1.8" strokeLinecap="round"/>
              </svg>
            </div>
            <div style={{ fontSize: 18, fontWeight: 700, color: SH.text, marginBottom: 6 }}>Delete Document?</div>
            <div style={{
              fontSize: 13.5, color: SH.muted, lineHeight: 1.5, padding: '0 8px',
            }}>
              <span style={{ fontWeight: 600, color: SH.text }}>Lease_Agreement_2026.pdf</span>
              {' '}will be permanently removed and cannot be recovered.
            </div>
          </div>

          {/* divider */}
          <div style={{ height: 1, background: SH.hairline }} />

          {/* buttons — stacked */}
          <div style={{
            display: 'flex', flexDirection: 'column',
          }}>
            <div style={{
              padding: '16px 24px', textAlign: 'center',
              fontSize: 16, fontWeight: 600, color: '#DC3545',
              borderBottom: `1px solid ${SH.hairline}`,
            }}>Delete Forever</div>
            <div style={{
              padding: '16px 24px', textAlign: 'center',
              fontSize: 16, fontWeight: 500, color: SH.text,
            }}>Cancel</div>
          </div>
        </div>
      </div>
    </Phone>
  );
}

Object.assign(window, {
  ScreenOnboard1, ScreenOnboard2, ScreenPermissions, ScreenHome,
  ScreenCamera, ScreenReview, ScreenDocDetail, ScreenPaywall,
  ScreenPostPurchase, ScreenSettings, ScreenWidgets, ScreenShareV2,
  ScreenImportChoicePopup, ScreenOCRProPopup, ScreenDeletePopup,
  SH, FONT, MONO,
});
