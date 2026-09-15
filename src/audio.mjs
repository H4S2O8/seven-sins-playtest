export class Soundscape {
  constructor() {
    this.context = null;
    this.volume = 0.35;
    this.muted = false;
  }
  start() {
    if (this.context) {
      this.context.resume();
      return;
    }
    const A = window.AudioContext || window.webkitAudioContext,
      c = (this.context = new A());
    this.master = c.createGain();
    this.master.gain.value = this.muted ? 0 : this.volume;
    this.master.connect(c.destination);
    const length = c.sampleRate * 5,
      buffer = c.createBuffer(1, length, c.sampleRate),
      data = buffer.getChannelData(0);
    let last = 0;
    for (let i = 0; i < length; i++) {
      last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02;
      data[i] = last * 3.5;
    }
    const noise = c.createBufferSource(),
      filter = c.createBiquadFilter(),
      g = c.createGain();
    noise.buffer = buffer;
    noise.loop = true;
    filter.type = "lowpass";
    filter.frequency.value = 440;
    g.gain.value = 0.1;
    noise.connect(filter).connect(g).connect(this.master);
    noise.start();
    this.drones = [];
    for (const [frequency, volume] of [
      [43, 0.08],
      [64.8, 0.035],
      [129.2, 0.008],
    ]) {
      const o = c.createOscillator(),
        gain = c.createGain();
      o.type = "sine";
      o.frequency.value = frequency;
      gain.gain.value = volume;
      o.connect(gain).connect(this.master);
      o.start();
      this.drones.push(o);
    }
    this.filter = filter;
  }
  setVolume(value) {
    this.volume = value;
    if (this.master)
      this.master.gain.setTargetAtTime(
        this.muted ? 0 : value,
        this.context.currentTime,
        0.1,
      );
  }
  setMuted(value) {
    this.muted = value;
    this.setVolume(this.volume);
  }
  room(index) {
    if (this.filter)
      this.filter.frequency.setTargetAtTime(
        280 + index * 65,
        this.context.currentTime,
        2,
      );
  }
  effect(freq = 100, duration = 0.1, type = "sine", volume = 0.06) {
    if (!this.context) return;
    const c = this.context,
      o = c.createOscillator(),
      g = c.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, c.currentTime);
    o.frequency.exponentialRampToValueAtTime(
      Math.max(25, freq * 0.35),
      c.currentTime + duration,
    );
    g.gain.setValueAtTime(volume, c.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + duration);
    o.connect(g).connect(this.master);
    o.start();
    o.stop(c.currentTime + duration);
  }
}
