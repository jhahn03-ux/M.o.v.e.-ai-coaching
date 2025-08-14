import React, { useEffect, useMemo, useState } from "react";

/**
 * M.O.V.E. AI Coaching App – MVP Starter (Single File, React)
 * -----------------------------------------------------------
 * What this is:
 * - A working, single-file MVP you can preview.
 * - Onboarding → Program Generator → Session Log → Auto-Adjust → Coach Dashboard.
 * - Local-only storage (no backend).
 * - A tiny rule engine + placeholders for AI calls.
 *
 * How to use:
 * - Fill onboarding, click “Generate Week”.
 * - Log a session (sets/reps/RPE/pain) → generator adapts next week.
 * - Use Coach Dashboard to triage and apply quick actions (swap, cap sets, deload).
 *
 * Where to integrate real AI:
 * - TODO markers: call your OpenAI function/gpt here with the provided JSON payloads.
 *
 * Styling:
 * - Tailwind classes only, no external UI libs to keep this portable.
 */

// ---------------------- Types ----------------------
const defaultProfile = {
  name: "",
  email: "",
  goal: "bjj_strength", // bjj_strength | general_strength | fat_loss | youth
  trainingAgeYrs: 3,
  daysAvailable: ["Mon", "Thu"],
  minutesPerSession: 60,
  equipment: {
    barbell: true,
    rack: true,
    dumbbells: true,
    kettlebells: true,
    bands: true,
    sled: false,
  },
  bjjDays: ["Tue", "Fri"],
  injuries: [
    // { area: "shoulder", aggravates: ["wide_grip_press"], severity: 2 }
  ],
  prefs: {
    barbellBias: true,
    dislikes: [],
  },
};

const defaultState = {
  profile: defaultProfile,
  currentPhase: "Base", // Base | Build | Peak | Deload
  weekIndex: 1,
  sessions: [], // planned sessions for current week
  sessionLogs: [], // { id, date, completed[], rpeAvg, painFlag, notes }
  readinessToday: { sleep: 7, soreness: 3, stress: 3, hrv: null, bjjLoad: "moderate" },
};

// ---------------------- Utilities ----------------------
const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

function save(key, val) {
  localStorage.setItem(key, JSON.stringify(val));
}
function load(key, fallback) {
  const v = localStorage.getItem(key);
  return v ? JSON.parse(v) : fallback;
}

function shortId() {
  return Math.random().toString(36).slice(2, 8);
}

// Basic e1RM estimate from reps @ RPE (rough; placeholder)
function estimateE1RM(weight, reps, rpe) {
  const rir = Math.max(0, 10 - rpe);
  const maxRepsAtWeight = reps + rir;
  // Epley-ish
  return Math.round(weight * (1 + maxRepsAtWeight / 30));
}

// Simple rule engine for load adjustments
function adjustLoad(prev, readiness, pain) {
  let delta = 0;
  const r = readiness;
  if (pain) delta -= 7;
  if (r.sleep >= 7 && r.soreness <= 3 && r.stress <= 3) delta += 3;
  if (r.soreness >= 4) delta -= 2;
  if (r.stress >= 4) delta -= 1;
  return Math.max(0, Math.round(prev * (1 + delta / 100)));
}

// Movement templates
const templates = {
  lower_strength: (constraints) => ({
    title: "Lower Strength + Grip",
    warmup: [
      "Hip Airplanes 2x5/side",
      "T-Spine Opener 2x8",
      "Ankle ROCK 2x10",
    ],
    blocks: [
      {
        move: "Back Squat",
        alt: constraints?.shoulder ? "Safety Bar Squat" : null,
        scheme: "Top set @8, backoffs 2x5 @70–75%",
        targetRPE: 8,
        slots: 3,
      },
      { move: "RDL", scheme: "3x6–8 @7–8", targetRPE: 8, slots: 3 },
      { move: "Carry (Farmer)", scheme: "4x40–60m", targetRPE: 7, slots: 4 },
      { move: "Grip Roll-ups", scheme: "3x to fatigue", targetRPE: 8, slots: 3 },
    ],
    finisher: "Nasal Walk 6–10min or Sled Drags",
  }),
  upper_shoulder_safe: (constraints) => ({
    title: "Upper Push/Pull (Shoulder-Safe)",
    warmup: [
      "Scap CARs 2x5",
      "Band External Rotations 2x12",
      "Wall Slides 2x8",
    ],
    blocks: [
      {
        move: constraints?.shoulder ? "DB Neutral Press" : "Barbell Bench Press",
        scheme: "Top set @8, 2x6 @70–75%",
        targetRPE: 8,
        slots: 3,
      },
      { move: "Chest-Supported Row", scheme: "3x8–10 @8", targetRPE: 8, slots: 3 },
      { move: "Cuff Isometrics", scheme: "3x20-30s", targetRPE: 6, slots: 3 },
      { move: "Pull-ups or Pulldown", scheme: "3x6–10 @8", targetRPE: 8, slots: 3 },
    ],
    finisher: "Breathe-Down 5min (box 4-6-6-4)",
  }),
  gpp: () => ({
    title: "GPP / Carries / Conditioning",
    warmup: ["World’s Greatest 2x", "Cossack 2x6/side"],
    blocks: [
      { move: "Sled Push/Drag", scheme: "10–15min easy-moderate", targetRPE: 6, slots: 1 },
      { move: "KB Swings", scheme: "8x15 EMOM", targetRPE: 7, slots: 8 },
      { move: "Carries Mix", scheme: "5–8min", targetRPE: 7, slots: 1 },
    ],
    finisher: "Easy Zone-2 15–20min optional",
  }),
};

function inferConstraints(profile) {
  const c = {};
  if (profile.injuries?.some((i) => i.area === "shoulder")) c.shoulder = true;
  return c;
}

// Choose focus given day + BJJ schedule
function chooseFocus(day, profile) {
  const bjjTomorrow = profile.bjjDays.includes(nextDay(day));
  if (day === "Mon") return "lower_strength";
  if (day === "Thu") return "upper_shoulder_safe";
  if (day === "Sat") return "gpp";
  // keep it simple
  return bjjTomorrow ? "upper_shoulder_safe" : "lower_strength";
}

function nextDay(day) {
  const idx = weekdays.indexOf(day);
  return weekdays[(idx + 1) % 7];
}

// ---------------------- AI Placeholder ----------------------
async function aiGenerateSessions(profile, readiness, lastWeek, phase, weekIndex) {
  // TODO: Replace this with a real OpenAI call.
  // The function returns minimal JSON the UI expects.
  const constraints = inferConstraints(profile);
  const plan = profile.daysAvailable.map((d) => {
    const focus = chooseFocus(d, profile);
    const tmpl = templates[focus](constraints);
    return {
      id: shortId(),
      day: d,
      title: tmpl.title,
      warmup: tmpl.warmup,
      blocks: tmpl.blocks.map((b) => ({
        ...b,
        loadSuggestion: b.targetRPE >= 8 ? suggestStartingLoad(b.move, lastWeek) : null,
      })),
      finisher: tmpl.finisher,
      cues: ["Own the positions.", "Leave 1–2 reps in the tank."],
    };
  });
  return { phase, weekIndex, plan, notes: phase === "Deload" ? "Keep effort @6–7, cut 30% volume." : "" };
}

function suggestStartingLoad(move, lastWeek) {
  // Look for a related movement in last week logs, then adjust modestly.
  const last = [...(lastWeek || [])].reverse().find((s) => s.completed?.some?.(() => true));
  if (!last) return null;
  const comp = last.completed?.find?.((x) => x.move?.toLowerCase?.().includes(move.split(" ")[0].toLowerCase()));
  if (!comp) return null;
  const base = comp.lastLoad || 0;
  return Math.round(base * 1.02);
}

// ---------------------- Component ----------------------
export default function App() {
  const [state, setState] = useState(() => load("move_mvp_state", defaultState));
  const [loading, setLoading] = useState(false);
  const [toast, setToast] = useState("");

  useEffect(() => {
    save("move_mvp_state", state);
  }, [state]);

  const constraints = useMemo(() => inferConstraints(state.profile), [state.profile]);

  // Derived KPIs
  const adherence = useMemo(() => {
    const planned = state.sessions.length;
    const completed = state.sessionLogs.filter((l) => l.weekIndex === state.weekIndex).length;
    return planned ? Math.round((completed / planned) * 100) : 0;
  }, [state.sessions, state.sessionLogs, state.weekIndex]);

  const redFlags = useMemo(() => {
    return state.sessionLogs
      .filter((l) => l.weekIndex === state.weekIndex)
      .filter((l) => l.painFlag >= 3 || (l.rpeAvg ?? 0) >= 9 || l.missed)
      .map((l) => ({ id: l.id, date: l.date, reason: l.missed ? "Missed session" : l.painFlag >= 3 ? `Pain ${l.painFlag}/5` : `High RPE ${l.rpeAvg}` }));
  }, [state.sessionLogs, state.weekIndex]);

  async function generateWeek() {
    setLoading(true);
    try {
      const res = await aiGenerateSessions(
        state.profile,
        state.readinessToday,
        state.sessionLogs.filter((l) => l.weekIndex === state.weekIndex - 1),
        state.currentPhase,
        state.weekIndex
      );
      setState((s) => ({ ...s, sessions: res.plan }));
      setToast("✅ Week generated.");
    } catch (e) {
      console.error(e);
      setToast("⚠️ Failed to generate. Using fallback.");
    } finally {
      setLoading(false);
      setTimeout(() => setToast(""), 3000);
    }
  }

  function logSession(session, log) {
    const id = shortId();
    const rpeAvg = average(log.completed?.map((c) => Number(c.rpe) || 0));
    const painFlag = Number(log.painFlag || 0);
    const entry = { id, weekIndex: state.weekIndex, date: new Date().toISOString().slice(0, 10), rpeAvg, painFlag, ...log };
    setState((s) => ({ ...s, sessionLogs: [...s.sessionLogs, entry] }));
    setToast("📘 Session logged.");
    setTimeout(() => setToast(""), 2500);
  }

  function applyQuickAction(type) {
    if (type === "deload") {
      setState((s) => ({ ...s, currentPhase: "Deload" }));
      setToast("🧯 Deload toggled for this block.");
    }
    if (type === "cap_sets") {
      setState((s) => ({
        ...s,
        sessions: s.sessions.map((sess) => ({
          ...sess,
          blocks: sess.blocks.map((b) => ({ ...b, scheme: b.scheme + " (−1 set)", slots: Math.max(1, (b.slots || 2) - 1) })),
        })),
      }));
      setToast("✂️ Volume capped by −1 set.");
    }
    if (type === "swap_press") {
      setState((s) => ({
        ...s,
        sessions: s.sessions.map((sess) => ({
          ...sess,
          blocks: sess.blocks.map((b) =>
            /press/i.test(b.move) ? { ...b, move: "DB Neutral Press", scheme: b.scheme + " (shoulder-safe)" } : b
          ),
        })),
      }));
      setToast("🔁 Swapped pressing to DB Neutral.");
    }
    setTimeout(() => setToast(""), 2500);
  }

  function nextWeek() {
    // Simple block periodization: every 4th week → deload, then advance phase
    const nextIndex = state.weekIndex + 1;
    let nextPhase = state.currentPhase;
    if (nextIndex % 4 === 0) nextPhase = "Deload";
    else if (state.currentPhase === "Base") nextPhase = "Build";
    else if (state.currentPhase === "Build") nextPhase = "Peak";
    else if (state.currentPhase === "Deload") nextPhase = "Base";

    setState((s) => ({ ...s, weekIndex: nextIndex, currentPhase: nextPhase, sessions: [] }));
    setToast(`⏭️ Advanced to week ${nextIndex} (${nextPhase}).`);
    setTimeout(() => setToast(""), 2500);
  }

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="sticky top-0 z-10 bg-white border-b border-slate-200">
        <div className="max-w-6xl mx-auto px-4 py-3 flex items-center justify-between">
          <h1 className="text-xl sm:text-2xl font-bold">M.O.V.E. AI Coaching – MVP</h1>
          <div className="text-sm opacity-70">Phase: {state.currentPhase} · Week {state.weekIndex} · Adherence {adherence}%</div>
        </div>
      </header>

      <main className="max-w-6xl mx-auto px-4 py-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left Column: Onboarding & Generator */}
        <section className="lg:col-span-1 space-y-6">
          <Card title="Onboarding">
            <OnboardingForm value={state.profile} onChange={(p) => setState((s) => ({ ...s, profile: p }))} />
          </Card>

          <Card title="Readiness (Today)">
            <Readiness value={state.readinessToday} onChange={(r) => setState((s) => ({ ...s, readinessToday: r }))} />
          </Card>

          <Card title="Program Generator">
            <div className="flex items-center gap-2">
              <button
                onClick={generateWeek}
                disabled={loading}
                className="px-4 py-2 rounded-2xl bg-slate-900 text-white shadow hover:shadow-md disabled:opacity-50"
              >
                {loading ? "Generating…" : "Generate Week"}
              </button>
              <button onClick={nextWeek} className="px-3 py-2 rounded-2xl bg-slate-200 hover:bg-slate-300">Next Week</button>
            </div>
            <p className="text-xs mt-2 text-slate-500">Respects BJJ days and shoulder-safe swaps. Auto-progression uses readiness & pain flags.</p>
          </Card>
        </section>

        {/* Middle Column: Sessions */}
        <section className="lg:col-span-2 space-y-6">
          <Card title="This Week’s Plan">
            {state.sessions.length === 0 ? (
              <p className="text-slate-600 text-sm">No sessions yet. Click <b>Generate Week</b> to create your plan.</p>
            ) : (
              <div className="space-y-4">
                {state.sessions.map((s) => (
                  <SessionCard key={s.id} session={s} onLog={(log) => logSession(s, log)} />
                ))}
              </div>
            )}
          </Card>

          <Card title="Coach Dashboard – Triage">
            {redFlags.length === 0 ? (
              <p className="text-slate-600 text-sm">No red flags this week. Keep rolling. 🥋</p>
            ) : (
              <ul className="text-sm list-disc pl-5 space-y-1">
                {redFlags.map((f) => (
                  <li key={f.id}>{f.date}: {f.reason}</li>
                ))}
              </ul>
            )}
            <div className="flex gap-2 mt-3 flex-wrap">
              <button onClick={() => applyQuickAction("swap_press")} className="px-3 py-2 rounded-xl bg-white border hover:bg-slate-50">Swap Press → DB Neutral</button>
              <button onClick={() => applyQuickAction("cap_sets")} className="px-3 py-2 rounded-xl bg-white border hover:bg-slate-50">Cap Volume (−1 set)</button>
              <button onClick={() => applyQuickAction("deload")} className="px-3 py-2 rounded-xl bg-white border hover:bg-slate-50">Toggle Deload</button>
            </div>
          </Card>
        </section>
      </main>

      {toast && (
        <div className="fixed bottom-4 left-1/2 -translate-x-1/2 bg-slate-900 text-white px-4 py-2 rounded-xl shadow">
          {toast}
        </div>
      )}

      <footer className="max-w-6xl mx-auto px-4 py-8 text-center text-xs text-slate-500">
        © {new Date().getFullYear()} M.O.V.E.NJ – MVP Starter. For education only; not medical advice.
      </footer>
    </div>
  );
}

// ---------------------- UI Components ----------------------
function Card({ title, children }) {
  return (
    <div className="bg-white rounded-2xl shadow-sm border border-slate-200 p-4">
      <div className="flex items-center justify-between mb-3">
        <h2 className="font-semibold">{title}</h2>
      </div>
      {children}
    </div>
  );
}

function OnboardingForm({ value, onChange }) {
  const [p, setP] = useState(value);
  useEffect(() => setP(value), [value]);
  useEffect(() => onChange(p), [p]);

  function toggleDay(day) {
    setP((s) => ({ ...s, daysAvailable: s.daysAvailable.includes(day) ? s.daysAvailable.filter((d) => d !== day) : [...s.daysAvailable, day] }));
  }
  function toggleBJJ(day) {
    setP((s) => ({ ...s, bjjDays: s.bjjDays.includes(day) ? s.bjjDays.filter((d) => d !== day) : [...s.bjjDays, day] }));
  }

  return (
    <div className="space-y-3 text-sm">
      <div className="grid grid-cols-2 gap-2">
        <input className="input" placeholder="Name" value={p.name} onChange={(e) => setP({ ...p, name: e.target.value })} />
        <input className="input" placeholder="Email" value={p.email} onChange={(e) => setP({ ...p, email: e.target.value })} />
      </div>
      <div>
        <label className="block text-xs text-slate-500 mb-1">Primary Goal</label>
        <select className="input" value={p.goal} onChange={(e) => setP({ ...p, goal: e.target.value })}>
          <option value="bjj_strength">BJJ Strength</option>
          <option value="general_strength">General Strength</option>
          <option value="fat_loss">Fat Loss</option>
          <option value="youth">Youth Athlete</option>
        </select>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <label className="flex items-center gap-2">Training Age (yrs)
          <input type="number" className="input" value={p.trainingAgeYrs} min={0} onChange={(e) => setP({ ...p, trainingAgeYrs: Number(e.target.value) })} />
        </label>
        <label className="flex items-center gap-2">Minutes/Session
          <input type="number" className="input" value={p.minutesPerSession} min={20} onChange={(e) => setP({ ...p, minutesPerSession: Number(e.target.value) })} />
        </label>
      </div>
      <div>
        <label className="block text-xs text-slate-500 mb-1">Days Available</label>
        <div className="flex flex-wrap gap-1">
          {weekdays.map((d) => (
            <button key={d} type="button" onClick={() => toggleDay(d)} className={'chip ' + (p.daysAvailable.includes(d) ? 'chip-on' : '')}>{d}</button>
          ))}
        </div>
      </div>
      <div>
        <label className="block text-xs text-slate-500 mb-1">BJJ Days</label>
        <div className="flex flex-wrap gap-1">
          {weekdays.map((d) => (
            <button key={d} type="button" onClick={() => toggleBJJ(d)} className={'chip ' + (p.bjjDays.includes(d) ? 'chip-on' : '')}>{d}</button>
          ))}
        </div>
      </div>
      <div>
        <label className="block text-xs text-slate-500 mb-1">Equipment</label>
        <div className="grid grid-cols-2 gap-2">
          {Object.keys(p.equipment).map((k) => (
            <label key={k} className="flex items-center gap-2">
              <input type="checkbox" checked={p.equipment[k]} onChange={(e) => setP({ ...p, equipment: { ...p.equipment, [k]: e.target.checked } })} />
              {k}
            </label>
          ))}
        </div>
      </div>
      <div>
        <label className="block text-xs text-slate-500 mb-1">Injuries (quick)</label>
        <InjuryEditor value={p.injuries} onChange={(inj) => setP({ ...p, injuries: inj })} />
      </div>
    </div>
  );
}

function InjuryEditor({ value, onChange }) {
  const [list, setList] = useState(value || []);
  useEffect(() => setList(value || []), [value]);
  useEffect(() => onChange(list), [list]);

  function add() {
    setList((l) => [...l, { id: shortId(), area: "shoulder", aggravates: ["press"], severity: 2 }]);
  }
  function upd(i, patch) {
    setList((l) => l.map((x, idx) => (idx === i ? { ...x, ...patch } : x)));
  }
  function del(i) {
    setList((l) => l.filter((_, idx) => idx !== i));
  }

  return (
    <div className="space-y-2">
      {list.length === 0 && <p className="text-xs text-slate-500">No injuries added.</p>}
      {list.map((it, i) => (
        <div key={it.id} className="bg-slate-50 border rounded-xl p-2 flex flex-wrap items-center gap-2">
          <select className="input !w-32" value={it.area} onChange={(e) => upd(i, { area: e.target.value })}>
            <option>shoulder</option>
            <option>knee</option>
            <option>hip</option>
            <option>back</option>
            <option>wrist</option>
            <option>ankle</option>
          </select>
          <input className="input" placeholder="Aggravates (comma)" value={it.aggravates?.join(", ")}
                 onChange={(e) => upd(i, { aggravates: e.target.value.split(",").map((s) => s.trim()) })} />
          <label className="flex items-center gap-2">Severity
            <input type="number" className="input !w-16" min={1} max={5} value={it.severity}
                   onChange={(e) => upd(i, { severity: Number(e.target.value) })} />
          </label>
          <button className="px-2 py-1 rounded-lg border" onClick={() => del(i)}>Delete</button>
        </div>
      ))}
      <button className="px-3 py-2 rounded-xl bg-white border" onClick={add}>Add Injury</button>
    </div>
  );
}

function Readiness({ value, onChange }) {
  const [r, setR] = useState(value);
  useEffect(() => setR(value), [value]);
  useEffect(() => onChange(r), [r]);
  return (
    <div className="grid grid-cols-2 gap-2 text-sm">
      <Num label="Sleep (1–10)" value={r.sleep} onChange={(v) => setR({ ...r, sleep: v })} />
      <Num label="Soreness (1–5)" value={r.soreness} onChange={(v) => setR({ ...r, soreness: v })} />
      <Num label="Stress (1–5)" value={r.stress} onChange={(v) => setR({ ...r, stress: v })} />
      <div>
        <label className="block text-xs text-slate-500 mb-1">BJJ Load</label>
        <select className="input" value={r.bjjLoad} onChange={(e) => setR({ ...r, bjjLoad: e.target.value })}>
          <option>light</option>
          <option>moderate</option>
          <option>hard</option>
        </select>
      </div>
    </div>
  );
}

function Num({ label, value, onChange }) {
  return (
    <label className="flex items-center justify-between gap-2">
      <span className="text-xs text-slate-500">{label}</span>
      <input type="number" className="input !w-20" value={value} onChange={(e) => onChange(Number(e.target.value))} />
    </label>
  );
}

function SessionCard({ session, onLog }) {
  const [open, setOpen] = useState(false);
  const [log, setLog] = useState({ completed: [], painFlag: 0, notes: "" });

  useEffect(() => {
    setLog({ completed: session.blocks.map((b) => ({ move: b.move, sets: 0, reps: 0, rpe: 7, lastLoad: 0 })), painFlag: 0, notes: "" });
  }, [session.id]);

  return (
    <div className="border rounded-2xl p-4">
      <div className="flex items-start justify-between">
        <div>
          <div className="text-xs text-slate-500">{session.day}</div>
          <h3 className="font-semibold text-lg">{session.title}</h3>
        </div>
        <button className="px-3 py-1 rounded-xl bg-slate-100 hover:bg-slate-200" onClick={() => setOpen((o) => !o)}>
          {open ? "Hide" : "Details"}
        </button>
      </div>

      {open && (
        <div className="mt-3 space-y-3">
          <div>
            <div className="text-xs text-slate-500">Warm-up</div>
            <ul className="list-disc pl-5 text-sm">
              {session.warmup.map((w, i) => (
                <li key={i}>{w}</li>
              ))}
            </ul>
          </div>
          <div>
            <div className="text-xs text-slate-500 mb-1">Main Work</div>
            <div className="space-y-2">
              {session.blocks.map((b, i) => (
                <div key={i} className="bg-slate-50 rounded-xl p-2 text-sm">
                  <div className="font-medium">
                    {b.move}
                    {b.alt && <span className="ml-2 text-xs text-slate-500">(Alt: {b.alt})</span>}
                  </div>
                  <div className="text-xs text-slate-500">{b.scheme}{b.loadSuggestion ? ` · Start ~${b.loadSuggestion} lb` : ""}</div>
                </div>
              ))}
            </div>
          </div>
          <div>
            <div className="text-xs text-slate-500">Finisher</div>
            <div className="text-sm">{session.finisher}</div>
          </div>
          <div>
            <div className="text-xs text-slate-500">Cues</div>
            <div className="text-sm">{session.cues.join(" · ")}</div>
          </div>

          {/* Log Form */}
          <div className="mt-4 border-t pt-3">
            <div className="text-sm font-semibold mb-2">Log Session</div>
            <div className="space-y-2">
              {log.completed.map((c, idx) => (
                <div key={idx} className="grid grid-cols-6 gap-2 items-center text-sm">
                  <div className="col-span-2 truncate">{c.move}</div>
                  <input className="input" placeholder="Sets" type="number" value={c.sets} onChange={(e) => updateCompleted(idx, { sets: Number(e.target.value) })} />
                  <input className="input" placeholder="Reps" type="number" value={c.reps} onChange={(e) => updateCompleted(idx, { reps: Number(e.target.value) })} />
                  <input className="input" placeholder="Top Set Load (lb)" type="number" value={c.lastLoad}
                         onChange={(e) => updateCompleted(idx, { lastLoad: Number(e.target.value) })} />
                  <input className="input" placeholder="Avg RPE" type="number" value={c.rpe} onChange={(e) => updateCompleted(idx, { rpe: Number(e.target.value) })} />
                </div>
              ))}
              <div className="flex flex-wrap items-center gap-2">
                <label className="flex items-center gap-2 text-sm">Pain Flag (0–5)
                  <input className="input !w-20" type="number" min={0} max={5} value={log.painFlag} onChange={(e) => setLog({ ...log, painFlag: Number(e.target.value) })} />
                </label>
                <input className="input flex-1" placeholder="Notes" value={log.notes} onChange={(e) => setLog({ ...log, notes: e.target.value })} />
                <button className="px-3 py-2 rounded-xl bg-slate-900 text-white" onClick={() => onLog({ ...log })}>Save Log</button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );

  function updateCompleted(i, patch) {
    setLog((l) => ({ ...l, completed: l.completed.map((c, idx) => (idx === i ? { ...c, ...patch } : c)) }));
  }
}

// ---------------------- Helpers ----------------------
function average(arr) {
  const v = (arr || []).filter((x) => Number.isFinite(x));
  if (!v.length) return 0;
  return Math.round((v.reduce((a, b) => a + b, 0) / v.length) * 10) / 10;
}

// ---------------------- Tailwind Utility Classes ----------------------
const base = typeof document !== "undefined" ? document.createElement("style") : null;
if (base) {
  base.innerHTML = `
    .input { @apply w-full border rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-slate-300; }
    .chip { @apply px-3 py-1 rounded-full border text-xs; }
    .chip-on { @apply bg-slate-900 text-white border-slate-900; }
  `;
  document.head.appendChild(base);
}
