let ctx: AudioContext | null = null;

function context(): AudioContext | null {
  try {
    if (!ctx) ctx = new AudioContext();
    if (ctx.state === "suspended") void ctx.resume();
    return ctx;
  } catch {
    return null;
  }
}

function tone(ac: AudioContext, freq: number, start: number, duration: number, gain: number) {
  const osc = ac.createOscillator();
  const amp = ac.createGain();
  osc.type = "sine";
  osc.frequency.setValueAtTime(freq, start);
  amp.gain.setValueAtTime(0, start);
  amp.gain.linearRampToValueAtTime(gain, start + 0.008);
  amp.gain.exponentialRampToValueAtTime(0.0001, start + duration);
  osc.connect(amp).connect(ac.destination);
  osc.start(start);
  osc.stop(start + duration + 0.02);
}

/** Short two-note confirmation chime. */
export function playSuccess() {
  const ac = context();
  if (!ac) return;
  const t = ac.currentTime;
  tone(ac, 1318.5, t, 0.09, 0.12);
  tone(ac, 1760, t + 0.07, 0.14, 0.1);
}

/** Low buzz used when delivery failed. */
export function playError() {
  const ac = context();
  if (!ac) return;
  const t = ac.currentTime;
  tone(ac, 220, t, 0.18, 0.14);
}
