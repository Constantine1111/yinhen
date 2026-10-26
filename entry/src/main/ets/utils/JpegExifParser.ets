export class RawExif {
  make: string = '';
  model: string = '';
  lensMake: string = '';
  lensModel: string = '';
  exposureTime: string = '';
  fNumber: string = '';
  iso: string = '';
  focalLength: string = '';
  focal35: string = '';
  program: string = '';
  dateTimeOriginal: string = '';
  dateTime: string = '';
  orientation: number = 1;
}

const PROGRAM_NAMES: string[] = [
  'Not defined',
  'Manual',
  'Normal program',
  'Aperture priority',
  'Shutter priority',
  'Creative program (biased toward depth of field)',
  'Creative program (biased toward fast shutter)',
  'Portrait mode',
  'Landscape mode'
];

function u16At(b: Uint8Array, o: number, le: boolean): number {
  return le ? (b[o] | (b[o + 1] << 8)) : ((b[o] << 8) | b[o + 1]);
}

function u32At(b: Uint8Array, o: number, le: boolean): number {
  const v: number = le
    ? (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24))
    : ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]);
  return v >>> 0;
}

function asciiAt(b: Uint8Array, o: number, maxLen: number): string {
  let s: string = '';
  for (let i = 0; i < maxLen; i++) {
    const c: number = b[o + i];
    if (c === 0) {
      break;
    }
    s += String.fromCharCode(c);
  }
  return s;
}

function typeSize(t: number): number {
  if (t === 3) {
    return 2;
  }
  if (t === 4 || t === 9) {
    return 4;
  }
  if (t === 5 || t === 10) {
    return 8;
  }
  return 1;
}

function rationalAt(b: Uint8Array, o: number, le: boolean): string {
  const n: number = u32At(b, o, le);
  const d: number = u32At(b, o + 4, le);
  if (d === 0) {
    return '';
  }
  return String(n / d);
}

function applyEntry(b: Uint8Array, le: boolean, tag: number, typ: number, cnt: number,
  vo: number, out: RawExif, t: number): void {
  if (tag === 0x010F) {
    if (typ === 2) {
      out.make = asciiAt(b, vo, cnt);
    }
  } else if (tag === 0x0110) {
    if (typ === 2) {
      out.model = asciiAt(b, vo, cnt);
    }
  } else if (tag === 0x0112) {
    out.orientation = u16At(b, vo, le);
  } else if (tag === 0x0132) {
    if (typ === 2) {
      out.dateTime = asciiAt(b, vo, cnt);
    }
  } else if (tag === 0x8769) {
    const sub: number = u32At(b, vo, le);
    parseIfd(b, t, le, sub, out, 1);
  } else if (tag === 0x829A) {
    if (typ === 5) {
      out.exposureTime = rationalAt(b, vo, le);
    }
  } else if (tag === 0x829D) {
    if (typ === 5) {
      out.fNumber = rationalAt(b, vo, le);
    }
  } else if (tag === 0x8822) {
    const v: number = u16At(b, vo, le);
    if (v >= 0 && v < PROGRAM_NAMES.length) {
      out.program = PROGRAM_NAMES[v];
    }
  } else if (tag === 0x8827) {
    out.iso = String(typ === 3 ? u16At(b, vo, le) : u32At(b, vo, le));
  } else if (tag === 0x9003) {
    if (typ === 2) {
      out.dateTimeOriginal = asciiAt(b, vo, cnt);
    }
  } else if (tag === 0x920A) {
    if (typ === 5) {
      out.focalLength = rationalAt(b, vo, le);
    }
  } else if (tag === 0xA405) {
    out.focal35 = String(u16At(b, vo, le));
  } else if (tag === 0xA433) {
    if (typ === 2) {
      out.lensMake = asciiAt(b, vo, cnt);
    }
  } else if (tag === 0xA434) {
    if (typ === 2) {
      out.lensModel = asciiAt(b, vo, cnt);
    }
  }
}

function parseIfd(b: Uint8Array, t: number, le: boolean, off: number, out: RawExif, depth: number): void {
  const base: number = t + off;
  if (depth > 1 || base < 0 || base + 2 > b.length) {
    return;
  }
  const count: number = u16At(b, base, le);
  if (count > 256) {
    return;
  }
  for (let i = 0; i < count; i++) {
    const eo: number = base + 2 + i * 12;
    if (eo + 12 > b.length) {
      return;
    }
    const tag: number = u16At(b, eo, le);
    const typ: number = u16At(b, eo + 2, le);
    const cnt: number = u32At(b, eo + 4, le);
    if (cnt === 0 || cnt > 1024) {
      continue;
    }
    const total: number = cnt * typeSize(typ);
    let vo: number = eo + 8;
    if (total > 4) {
      vo = t + u32At(b, eo + 8, le);
    }
    if (vo < 0 || vo + total > b.length) {
      continue;
    }
    applyEntry(b, le, tag, typ, cnt, vo, out, t);
  }
}

export function parseJpegExif(buf: Uint8Array): RawExif | undefined {
  const b: Uint8Array = buf;
  if (b.length < 12 || b[0] !== 0xFF || b[1] !== 0xD8) {
    return undefined;
  }
  let p: number = 2;
  let exifStart: number = -1;
  while (p + 4 <= b.length) {
    if (b[p] !== 0xFF) {
      p++;
      continue;
    }
    const marker: number = b[p + 1];
    if (marker === 0xD9 || marker === 0xDA) {
      break;
    }
    if (marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      p += 2;
      continue;
    }
    const segLen: number = ((b[p + 2] << 8) | b[p + 3]) + 2;
    if (marker === 0xE1 && p + 10 <= b.length && b[p + 4] === 0x45 && b[p + 5] === 0x78 &&
      b[p + 6] === 0x69 && b[p + 7] === 0x66 && b[p + 8] === 0x00 && b[p + 9] === 0x00) {
      exifStart = p + 10;
      break;
    }
    if (segLen < 4) {
      break;
    }
    p += segLen;
  }
  if (exifStart < 0 || exifStart + 8 > b.length) {
    return undefined;
  }
  const t: number = exifStart;
  const isLE: boolean = b[t] === 0x49 && b[t + 1] === 0x49;
  if (!isLE && !(b[t] === 0x4D && b[t + 1] === 0x4D)) {
    return undefined;
  }
  const ifd0: number = u32At(b, t + 4, isLE);
  if (ifd0 === 0 || t + ifd0 + 2 > b.length) {
    return undefined;
  }
  const out: RawExif = new RawExif();
  parseIfd(b, t, isLE, ifd0, out, 0);
  return out;
}
