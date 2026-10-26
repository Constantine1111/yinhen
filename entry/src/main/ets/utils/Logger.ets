import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export class LogEntry {
  time: string = '';
  level: number = 0; // 0=info 1=warn 2=error
  msg: string = '';

  constructor(time: string, level: number, msg: string) {
    this.time = time;
    this.level = level;
    this.msg = msg;
  }
}

export class Logger {
  private static entries: LogEntry[] = [];
  private static readonly MAX_ENTRIES: number = 1000;
  private static readonly MAX_FILE_SIZE: number = 512 * 1024;
  private static readonly ROTATE_KEEP: number = 256 * 1024;
  private static filePath: string = '';
  private static writtenBytes: number = 0;
  private static initialized: boolean = false;

  static init(context: common.UIAbilityContext): void {
    if (Logger.initialized) {
      return;
    }
    try {
      const dir: string = `${context.filesDir}/logs`;
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      Logger.filePath = `${dir}/yinhen.log`;
      Logger.loadTail();
      Logger.initialized = true;
    } catch (err) {
      console.error(`Logger init failed: ${JSON.stringify(err)}`);
    }
  }

  static info(msg: string): void {
    Logger.append(0, msg);
    console.info(msg);
  }

  static warn(msg: string): void {
    Logger.append(1, msg);
    console.warn(msg);
  }

  static error(msg: string): void {
    Logger.append(2, msg);
    console.error(msg);
  }

  static getEntries(): LogEntry[] {
    return Logger.entries;
  }

  static formatAll(): string {
    let out: string = '';
    for (let i = 0; i < Logger.entries.length; i++) {
      const e: LogEntry = Logger.entries[i];
      out += `${e.time} ${e.level === 2 ? '[E]' : e.level === 1 ? '[W]' : '[I]'} ${e.msg}\n`;
    }
    return out;
  }

  static clear(): void {
    Logger.entries = [];
    Logger.writtenBytes = 0;
    if (Logger.filePath.length > 0) {
      try {
        if (fileIo.accessSync(Logger.filePath)) {
          fileIo.unlinkSync(Logger.filePath);
        }
      } catch (err) {
        console.error(`Logger clear failed: ${JSON.stringify(err)}`);
      }
    }
  }

  private static append(level: number, msg: string): void {
    const time: string = Logger.now();
    Logger.entries.push(new LogEntry(time, level, msg));
    if (Logger.entries.length > Logger.MAX_ENTRIES) {
      Logger.entries.splice(0, Logger.entries.length - Logger.MAX_ENTRIES);
    }
    if (Logger.filePath.length === 0) {
      return;
    }
    try {
      const line: string = `${time}\t${level}\t${msg}\n`;
      if (Logger.writtenBytes > Logger.MAX_FILE_SIZE) {
        Logger.rotate();
      }
      const f: fileIo.File = fileIo.openSync(Logger.filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
      fileIo.writeSync(f.fd, line);
      fileIo.closeSync(f);
      Logger.writtenBytes += line.length;
    } catch (err) {
      console.error(`Logger append failed: ${JSON.stringify(err)}`);
    }
  }

  private static loadTail(): void {
    try {
      if (Logger.filePath.length === 0 || !fileIo.accessSync(Logger.filePath)) {
        return;
      }
      const stat: fileIo.Stat = fileIo.statSync(Logger.filePath);
      const size: number = stat.size;
      if (size === 0) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(Logger.filePath, fileIo.OpenMode.READ_ONLY);
      const content: ArrayBuffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, content);
      fileIo.closeSync(file);
      Logger.writtenBytes = size;
      const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(content));
      const lines: string[] = text.split('\n');
      const start: number = Math.max(0, lines.length - Logger.MAX_ENTRIES);
      for (let i = start; i < lines.length; i++) {
        const line: string = lines[i];
        if (line.length === 0) {
          continue;
        }
        const t1: number = line.indexOf('\t');
        if (t1 < 0) {
          continue;
        }
        const t2: number = line.indexOf('\t', t1 + 1);
        if (t2 < 0) {
          continue;
        }
        const time: string = line.substring(0, t1);
        const level: number = Number(line.substring(t1 + 1, t2));
        const msg: string = line.substring(t2 + 1);
        Logger.entries.push(new LogEntry(time, level, msg));
      }
    } catch (err) {
      console.error(`Logger loadTail failed: ${JSON.stringify(err)}`);
    }
  }

  private static rotate(): void {
    try {
      if (!fileIo.accessSync(Logger.filePath)) {
        Logger.writtenBytes = 0;
        return;
      }
      const size: number = fileIo.statSync(Logger.filePath).size;
      if (size <= Logger.ROTATE_KEEP) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(Logger.filePath, fileIo.OpenMode.READ_ONLY);
      const content: ArrayBuffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, content);
      fileIo.closeSync(file);
      const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(content));
      const keep: string = text.substring(size - Logger.ROTATE_KEEP);
      const nl: number = keep.indexOf('\n');
      const trimmed: string = nl >= 0 ? keep.substring(nl + 1) : keep;
      fileIo.unlinkSync(Logger.filePath);
      const out: fileIo.File = fileIo.openSync(Logger.filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(out.fd, trimmed);
      fileIo.closeSync(out);
      Logger.writtenBytes = trimmed.length;
    } catch (err) {
      console.error(`Logger rotate failed: ${JSON.stringify(err)}`);
    }
  }

  private static now(): string {
    const d: Date = new Date();
    const p2: (n: number) => string = (n: number): string => {
      if (n < 10) {
        return `0${n}`;
      }
      return `${n}`;
    };
    const p3: (n: number) => string = (n: number): string => {
      if (n < 10) {
        return `00${n}`;
      }
      if (n < 100) {
        return `0${n}`;
      }
      return `${n}`;
    };
    return `${p2(d.getMonth() + 1)}-${p2(d.getDate())} ${p2(d.getHours())}:${p2(d.getMinutes())}:` +
      `${p2(d.getSeconds())}.${p3(d.getMilliseconds())}`;
  }
}
