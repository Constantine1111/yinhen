import { Logger } from './Logger';
import { picker, fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import {
  ExifInfo,
  formatExposureTime,
  formatAperture,
  formatFocal,
  cleanNum,
  formatDate,
  mapProgram,
  orientationDegrees
} from '../model/WatermarkModels';
import { RawExif, parseJpegExif } from './JpegExifParser';

const ORIG_CAP: number = 4096;

export class HdrJpegParts {
  isoSeg: Uint8Array = new Uint8Array(0);
  mpfSeg: Uint8Array = new Uint8Array(0);
  t35Seg: Uint8Array = new Uint8Array(0);
  gainmap: Uint8Array = new Uint8Array(0);
  entry0SizePos: number = 0;
  entry1OffPos: number = 0;
  entry1SizePos: number = 0;
  bigEndian: boolean = true;
  offsetBasis: number = 0;
}

export class PersonalLogoResult {
  aspect: number = 0;
  hasColor: boolean = false;
}

export class ImageTools {
  static async pickImageUris(maxNumber: number): Promise<string[]> {
    const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = maxNumber;
    const photoPicker: picker.PhotoViewPicker = new picker.PhotoViewPicker();
    const result: picker.PhotoSelectResult = await photoPicker.select(options);
    return result.photoUris;
  }

  static async readExif(uri: string): Promise<ExifInfo | undefined> {
    let file: fileIo.File | undefined = undefined;
    const info: ExifInfo = new ExifInfo();
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const source: image.ImageSource = image.createImageSource(file.fd);
      try {
        info.make = await ImageTools.prop(source, image.PropertyKey.MAKE);
        info.model = await ImageTools.prop(source, image.PropertyKey.MODEL);
        info.lensMake = await ImageTools.prop(source, image.PropertyKey.LENS_MAKE);
        info.lensModel = await ImageTools.prop(source, image.PropertyKey.LENS_MODEL);
        info.exposureTime = formatExposureTime(await ImageTools.prop(source, image.PropertyKey.EXPOSURE_TIME));
        info.fNumber = formatAperture(await ImageTools.prop(source, image.PropertyKey.F_NUMBER));
        let iso: string = cleanNum(await ImageTools.prop(source, image.PropertyKey.PHOTOGRAPHIC_SENSITIVITY));
        if (iso === '') {
          iso = cleanNum(await ImageTools.prop(source, image.PropertyKey.ISO_SPEED_RATINGS));
        }
        info.iso = iso;
        info.focalLength = formatFocal(await ImageTools.prop(source, image.PropertyKey.FOCAL_LENGTH));
        info.focal35 = cleanNum(await ImageTools.prop(source, image.PropertyKey.FOCAL_LENGTH_IN_35_MM_FILM));
        info.program = mapProgram(await ImageTools.prop(source, image.PropertyKey.EXPOSURE_PROGRAM));
        info.dateTime = formatDate(await ImageTools.prop(source, image.PropertyKey.DATE_TIME_ORIGINAL));
      } catch (err) {
        Logger.error(`WMEXIF imageKit read failed err=${JSON.stringify(err)}`);
      }
      await source.release();
    } catch (err) {
      Logger.error(`WMEXIF open uri=${uri} failed err=${JSON.stringify(err)}`);
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
    const needManual: boolean = info.make === '' || info.model === '' || info.exposureTime === '' ||
      info.fNumber === '' || info.iso === '' || info.focalLength === '' || info.dateTime === '';
    if (needManual) {
      ImageTools.fillFromJpegParse(uri, info);
    }
    Logger.info(`WMEXIF uri=${uri} make=[${info.make}] model=[${info.model}] lensMake=[${info.lensMake}] ` +
      `lensModel=[${info.lensModel}] exposure=[${info.exposureTime}] fn=[${info.fNumber}] iso=[${info.iso}] ` +
      `focal=[${info.focalLength}] focal35=[${info.focal35}] program=[${info.program}] date=[${info.dateTime}]`);
    return info;
  }

  // 单属性读取：照片缺少该 EXIF 字段时返回空串（正常情况，走手动解析回退）
  private static async prop(source: image.ImageSource, key: image.PropertyKey): Promise<string> {
    try {
      return (await source.getImageProperty(key)).trim();
    } catch (err) {
      return '';
    }
  }

  private static fillFromJpegParse(uri: string, info: ExifInfo): void {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const head: ArrayBuffer = new ArrayBuffer(262144);
      const readLen: number = fileIo.readSync(file.fd, head);
      const headBytes: Uint8Array = new Uint8Array(head, 0, Math.min(32, readLen));
      let hex: string = '';
      for (let i = 0; i < headBytes.length; i++) {
        hex += headBytes[i].toString(16).padStart(2, '0') + ' ';
      }
      Logger.info(`WMEXIF manual head32 readLen=${readLen} [${hex.trim()}]`);
      const raw: RawExif | undefined = parseJpegExif(new Uint8Array(head, 0, readLen));
      if (raw === undefined) {
        Logger.error('WMEXIF manual parse: no Exif APP1 found');
        return;
      }
      if (info.make === '') {
        info.make = raw.make.trim();
      }
      if (info.model === '') {
        info.model = raw.model.trim();
      }
      if (info.lensMake === '') {
        info.lensMake = raw.lensMake.trim();
      }
      if (info.lensModel === '') {
        info.lensModel = raw.lensModel.trim();
      }
      if (info.exposureTime === '') {
        info.exposureTime = formatExposureTime(raw.exposureTime);
      }
      if (info.fNumber === '') {
        info.fNumber = formatAperture(raw.fNumber);
      }
      if (info.iso === '') {
        info.iso = cleanNum(raw.iso);
      }
      if (info.focalLength === '') {
        info.focalLength = formatFocal(raw.focalLength);
      }
      if (info.focal35 === '') {
        info.focal35 = cleanNum(raw.focal35);
      }
      if (info.program === '') {
        info.program = mapProgram(raw.program);
      }
      if (info.dateTime === '') {
        info.dateTime = formatDate(raw.dateTimeOriginal !== '' ? raw.dateTimeOriginal : raw.dateTime);
      }
      Logger.info(`WMEXIF manual parsed make=[${raw.make}] model=[${raw.model}] lensMake=[${raw.lensMake}] ` +
        `lensModel=[${raw.lensModel}] exposure=[${raw.exposureTime}] fn=[${raw.fNumber}] iso=[${raw.iso}] ` +
        `focal=[${raw.focalLength}] focal35=[${raw.focal35}] program=[${raw.program}] ` +
        `dto=[${raw.dateTimeOriginal}] dt=[${raw.dateTime}] orient=[${raw.orientation}]`);
    } catch (err) {
      Logger.error(`WMEXIF manual parse failed err=${JSON.stringify(err)}`);
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  static async decodeScaled(uri: string, longEdge: number, ratio: number): Promise<image.PixelMap | undefined> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const source: image.ImageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      const origW: number = info.size.width;
      const origH: number = info.size.height;
      let orient: string = 'Top-left';
      try {
        orient = await source.getImageProperty(image.PropertyKey.ORIENTATION,
          { index: 0, defaultValue: 'Top-left' });
      } catch (err) {
        orient = 'Top-left';
      }
      const rotateDeg: number = orientationDegrees(orient);
      const swap: boolean = rotateDeg === 90 || rotateDeg === 270;
      const dispW: number = swap ? origH : origW;
      const dispH: number = swap ? origW : origH;
      // 中心裁切后的目标比例尺寸（ratio<=0 表示保持原图比例不裁切）
      let cropW: number = dispW;
      let cropH: number = dispH;
      if (ratio > 0) {
        if (dispW / dispH > ratio) {
          cropW = dispH * ratio;
        } else {
          cropH = dispW / ratio;
        }
      }
      const maxEdge: number = longEdge > 0 ? longEdge : ORIG_CAP;
      // 解码缩放：让裁切区长边尽量达到 maxEdge，同时解码总像素不超过 ORIG_CAP²（内存上限）
      let scale: number = Math.min(1, maxEdge / Math.max(cropW, cropH));
      const pxLimit: number = ORIG_CAP * ORIG_CAP;
      const px: number = origW * origH * scale * scale;
      if (px > pxLimit) {
        scale = scale * Math.sqrt(pxLimit / px);
      }
      const targetW: number = Math.max(1, Math.round(origW * scale));
      const targetH: number = Math.max(1, Math.round(origH * scale));
      const decOptions: image.DecodingOptions = {
        desiredSize: { width: targetW, height: targetH }
      };
      const pm: image.PixelMap = await source.createPixelMap(decOptions);
      await source.release();
      if (rotateDeg !== 0) {
        try {
          await pm.rotate(rotateDeg);
        } catch (err) {
          Logger.error(`ImageTools rotate failed: ${JSON.stringify(err)}`);
        }
      }
      // 旋转后在解码图上做中心裁切（crop 原地修改）
      if (ratio > 0) {
        const post: image.ImageInfo = await pm.getImageInfo();
        const pw: number = post.size.width;
        const ph: number = post.size.height;
        let cw: number = pw;
        let ch: number = ph;
        if (pw / ph > ratio) {
          cw = ph * ratio;
        } else {
          ch = pw / ratio;
        }
        const rx: number = Math.round((pw - cw) / 2);
        const ry: number = Math.round((ph - ch) / 2);
        try {
          await pm.crop({
            size: {
              width: Math.min(Math.round(cw), pw - rx),
              height: Math.min(Math.round(ch), ph - ry)
            },
            x: rx,
            y: ry
          });
        } catch (err) {
          Logger.error(`ImageTools crop failed: ${JSON.stringify(err)}`);
        }
      }
      return pm;
    } catch (err) {
      Logger.error(`ImageTools decode failed: ${JSON.stringify(err)}`);
      return undefined;
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  static async makeBlurredBg(uri: string, blurPct: number): Promise<image.PixelMap | undefined> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const source: image.ImageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      const origW: number = info.size.width;
      const origH: number = info.size.height;
      let orient: string = 'Top-left';
      try {
        orient = await source.getImageProperty(image.PropertyKey.ORIENTATION,
          { index: 0, defaultValue: 'Top-left' });
      } catch (err) {
        orient = 'Top-left';
      }
      const rotateDeg: number = orientationDegrees(orient);
      const scale: number = Math.min(1, 512 / Math.max(origW, origH));
      const tw: number = Math.max(1, Math.round(origW * scale));
      const th: number = Math.max(1, Math.round(origH * scale));
      const pm: image.PixelMap = await source.createPixelMap(
        { desiredSize: { width: tw, height: th } });
      await source.release();
      if (rotateDeg !== 0) {
        try {
          await pm.rotate(rotateDeg);
        } catch (err) {
          Logger.error(`ImageTools bg rotate failed: ${JSON.stringify(err)}`);
        }
      }
      const radius: number = Math.min(40, Math.max(1, Math.round(blurPct)));
      const filter: effectKit.Filter = effectKit.createEffect(pm);
      filter.blur(radius);
      const out: image.PixelMap = await filter.getEffectPixelMap();
      if (out !== pm) {
        pm.release();
      }
      return out;
    } catch (err) {
      Logger.error(`ImageTools makeBlurredBg failed: ${JSON.stringify(err)}`);
      return undefined;
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  private static segAscii(b: Uint8Array, start: number, max: number): string {
    let s: string = '';
    const end: number = Math.min(b.length, start + max);
    for (let i = start; i < end; i++) {
      const c: number = b[i];
      if (c === 0) {
        break;
      }
      s += (c >= 32 && c < 127) ? String.fromCharCode(c) : '.';
    }
    return s;
  }

  private static containsKeyword(b: Uint8Array, key: string): boolean {
    const kLen: number = key.length;
    const bLen: number = b.length;
    for (let i = 0; i <= bLen - kLen; i++) {
      let match: boolean = true;
      for (let j = 0; j < kLen; j++) {
        if (b[i + j] !== key.charCodeAt(j)) {
          match = false;
          break;
        }
      }
      if (match) {
        return true;
      }
    }
    return false;
  }

  private static asciiEq(b: Uint8Array, start: number, s: string): boolean {
    if (start + s.length > b.length) {
      return false;
    }
    for (let i = 0; i < s.length; i++) {
      if (b[start + i] !== s.charCodeAt(i)) {
        return false;
      }
    }
    return true;
  }

  private static readU16(b: Uint8Array, p: number, be: boolean): number {
    return be ? ((b[p] << 8) | b[p + 1]) : ((b[p + 1] << 8) | b[p]);
  }

  private static readU32(b: Uint8Array, p: number, be: boolean): number {
    if (be) {
      return (((b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]) >>> 0);
    }
    return (((b[p + 3] << 24) | (b[p + 2] << 16) | (b[p + 1] << 8) | b[p]) >>> 0);
  }

  private static writeU32(b: Uint8Array, p: number, v: number, be: boolean): void {
    if (be) {
      b[p] = (v >>> 24) & 0xFF;
      b[p + 1] = (v >>> 16) & 0xFF;
      b[p + 2] = (v >>> 8) & 0xFF;
      b[p + 3] = v & 0xFF;
    } else {
      b[p] = v & 0xFF;
      b[p + 1] = (v >>> 8) & 0xFF;
      b[p + 2] = (v >>> 16) & 0xFF;
      b[p + 3] = (v >>> 24) & 0xFF;
    }
  }

  private static writeU16(b: Uint8Array, p: number, v: number, be: boolean): void {
    if (be) {
      b[p] = (v >>> 8) & 0xFF;
      b[p + 1] = v & 0xFF;
    } else {
      b[p] = v & 0xFF;
      b[p + 1] = (v >>> 8) & 0xFF;
    }
  }

  // 读取原片文件头，提取完整 EXIF APP1 段（含 FFE1 标记与段长），非 JPEG 或无 EXIF 返回 undefined
  static extractExifSegment(uri: string): Uint8Array | undefined {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const head: ArrayBuffer = new ArrayBuffer(262144);
      const readLen: number = fileIo.readSync(file.fd, head);
      if (readLen < 12) {
        return undefined;
      }
      const b: Uint8Array = new Uint8Array(head, 0, readLen);
      if (b[0] !== 0xFF || b[1] !== 0xD8) {
        return undefined;
      }
      let p: number = 2;
      while (p + 4 <= readLen) {
        if (b[p] !== 0xFF) {
          break;
        }
        const marker: number = b[p + 1];
        if (marker === 0xDA || marker === 0xD9) {
          break;
        }
        if (marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          p += 2;
          continue;
        }
        const segLen: number = (b[p + 2] << 8) | b[p + 3];
        if (marker === 0xE1 && ImageTools.asciiEq(b, p + 4, 'Exif') &&
          b[p + 8] === 0x00 && b[p + 9] === 0x00) {
          const total: number = segLen + 2;
          if (segLen >= 8 && p + total <= readLen) {
            return b.slice(p, p + total);
          }
          return undefined;
        }
        if (segLen < 2) {
          break;
        }
        p += segLen + 2;
      }
      return undefined;
    } catch (err) {
      Logger.error(`WMEXIF extract seg failed: ${JSON.stringify(err)}`);
      return undefined;
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  // 内联修正继承的 EXIF：Orientation→1（导出画面已按原方向转正）、PixelX/YDimension→输出尺寸
  // 只改 IFD 内联值（≤4 字节），段长与所有偏移不变
  static patchExifSegment(seg: Uint8Array, outW: number, outH: number): void {
    try {
      const t: number = 10;
      if (seg.length < t + 8 || seg[0] !== 0xFF || seg[1] !== 0xE1 ||
        !ImageTools.asciiEq(seg, 4, 'Exif')) {
        return;
      }
      const le: boolean = seg[t] === 0x49 && seg[t + 1] === 0x49;
      const be: boolean = seg[t] === 0x4D && seg[t + 1] === 0x4D;
      if (!le && !be) {
        return;
      }
      const bigEnd: boolean = !le;
      const ifd0: number = t + ImageTools.readU32(seg, t + 4, bigEnd);
      if (ifd0 < 0 || ifd0 + 2 > seg.length) {
        return;
      }
      const cnt: number = ImageTools.readU16(seg, ifd0, bigEnd);
      if (cnt > 256) {
        return;
      }
      let exifIfd: number = -1;
      let orientPatched: boolean = false;
      for (let i = 0; i < cnt; i++) {
        const e: number = ifd0 + 2 + i * 12;
        if (e + 12 > seg.length) {
          break;
        }
        const tag: number = ImageTools.readU16(seg, e, bigEnd);
        if (tag === 0x0112 && ImageTools.readU16(seg, e + 2, bigEnd) === 3 &&
          ImageTools.readU32(seg, e + 4, bigEnd) === 1) {
          ImageTools.writeU16(seg, e + 8, 1, bigEnd);
          orientPatched = true;
        } else if (tag === 0x8769) {
          exifIfd = t + ImageTools.readU32(seg, e + 8, bigEnd);
        }
      }
      let dimPatched: number = 0;
      if (exifIfd >= 0 && exifIfd + 2 <= seg.length) {
        const ecnt: number = ImageTools.readU16(seg, exifIfd, bigEnd);
        if (ecnt <= 512) {
          for (let i = 0; i < ecnt; i++) {
            const e: number = exifIfd + 2 + i * 12;
            if (e + 12 > seg.length) {
              break;
            }
            const tag: number = ImageTools.readU16(seg, e, bigEnd);
            if (tag !== 0xA002 && tag !== 0xA003) {
              continue;
            }
            const typ: number = ImageTools.readU16(seg, e + 2, bigEnd);
            if (ImageTools.readU32(seg, e + 4, bigEnd) !== 1) {
              continue;
            }
            const v: number = tag === 0xA002 ? Math.round(outW) : Math.round(outH);
            if (typ === 3 && v <= 0xFFFF) {
              ImageTools.writeU16(seg, e + 8, v, bigEnd);
              dimPatched++;
            } else if (typ === 4) {
              ImageTools.writeU32(seg, e + 8, v, bigEnd);
              dimPatched++;
            }
          }
        }
      }
      Logger.info(`WMEXIF patch: orient=${orientPatched ? 1 : 0} dims=${dimPatched} out=${Math.round(outW)}x${Math.round(outH)}`);
    } catch (err) {
      Logger.error(`WMEXIF patch failed: ${JSON.stringify(err)}`);
    }
  }

  // 在 JPEG SOI 后插入完整段（如继承的 EXIF APP1），返回新数组
  private static insertSegmentAfterSoi(jpeg: Uint8Array, seg: Uint8Array): Uint8Array {
    const out: Uint8Array = new Uint8Array(jpeg.length + seg.length);
    out.set(jpeg.subarray(0, 2), 0);
    out.set(seg, 2);
    out.set(jpeg.subarray(2), 2 + seg.length);
    return out;
  }

  private static logJpegStructure(tag: string, f: Uint8Array): void {
    try {
      const head: Uint8Array = f.subarray(0, Math.min(f.length, 524288));
      const segs: string[] = [];
      let pos: number = 2;
      while (pos + 4 <= head.length && segs.length < 24) {
        if (head[pos] !== 0xFF) {
          break;
        }
        const marker: number = head[pos + 1];
        if (marker === 0xD8 || marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          pos += 2;
          continue;
        }
        if (marker === 0xDA || marker === 0xD9) {
          segs.push(`FF${marker.toString(16).padStart(2, '0').toUpperCase()}*`);
          break;
        }
        const len: number = (head[pos + 2] << 8) | head[pos + 3];
        segs.push(`FF${marker.toString(16).padStart(2, '0').toUpperCase()}:${len}` +
          `[${ImageTools.segAscii(head, pos + 4, 24)}]`);
        pos += 2 + len;
      }
      const keys: string[] = ['hdrgm', 'urn:iso:std', 'MPF', 'ainMap', 'Vivid', 'OPIEcom'];
      const hits: string[] = [];
      for (let i = 0; i < keys.length; i++) {
        if (ImageTools.containsKeyword(head, keys[i])) {
          hits.push(keys[i]);
        }
      }
      Logger.info(`WMSEG ${tag} size=${f.length} segs=${segs.join(' ')} keys=[${hits.join(',')}]`);
    } catch (err) {
      Logger.error(`WMSEG ${tag} failed: ${JSON.stringify(err)}`);
    }
  }

  static async readHdrJpegParts(uri: string): Promise<HdrJpegParts | undefined> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const size: number = fileIo.statSync(file.fd).size;
      if (size <= 4) {
        return undefined;
      }
      const buf: ArrayBuffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buf);
      const f: Uint8Array = new Uint8Array(buf);
      if (f[0] !== 0xFF || f[1] !== 0xD8) {
        return undefined;
      }
      ImageTools.logJpegStructure('SRC', f);
      let isoSeg: Uint8Array = new Uint8Array(0);
      let mpfSeg: Uint8Array = new Uint8Array(0);
      let t35Seg: Uint8Array = new Uint8Array(0);
      let sosPos: number = -1;
      let pos: number = 2;
      while (pos + 4 <= f.length) {
        if (f[pos] !== 0xFF) {
          break;
        }
        const marker: number = f[pos + 1];
        if (marker === 0xD8 || marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          pos += 2;
          continue;
        }
        if (marker === 0xDA) {
          sosPos = pos;
          break;
        }
        if (marker === 0xD9) {
          break;
        }
        const len: number = (f[pos + 2] << 8) | f[pos + 3];
        if (marker === 0xE2) {
          const p0: number = pos + 4;
          if (isoSeg.length === 0 && ImageTools.asciiEq(f, p0, 'urn:iso:std:iso:ts:21496')) {
            isoSeg = f.slice(pos, pos + 2 + len);
          } else if (mpfSeg.length === 0 && ImageTools.asciiEq(f, p0, 'MPF')) {
            mpfSeg = f.slice(pos, pos + 2 + len);
          }
        } else if (marker === 0xE8) {
          if (t35Seg.length === 0 && ImageTools.asciiEq(f, pos + 4, 'ITUT35')) {
            t35Seg = f.slice(pos, pos + 2 + len);
          }
        }
        pos += 2 + len;
      }
      if (isoSeg.length === 0 || mpfSeg.length === 0 || sosPos < 0) {
        Logger.info('WMHDR readHdrJpegParts: not dual-layer HDR, fallback SDR');
        return undefined;
      }
      const t0: number = 8;
      let bigEndian: boolean = true;
      if (mpfSeg[t0] === 0x49 && mpfSeg[t0 + 1] === 0x49) {
        bigEndian = false;
      } else if (!(mpfSeg[t0] === 0x4D && mpfSeg[t0 + 1] === 0x4D)) {
        Logger.info('WMHDR readHdrJpegParts: bad MPF tiff header');
        return undefined;
      }
      const ifdOff: number = ImageTools.readU32(mpfSeg, t0 + 4, bigEndian);
      const ifd: number = t0 + ifdOff;
      const cnt: number = ImageTools.readU16(mpfSeg, ifd, bigEndian);
      let mpeDataOff: number = -1;
      let numImages: number = -1;
      for (let i = 0; i < cnt; i++) {
        const e: number = ifd + 2 + i * 12;
        const tag: number = ImageTools.readU16(mpfSeg, e, bigEndian);
        if (tag === 0xB002) {
          mpeDataOff = ImageTools.readU32(mpfSeg, e + 8, bigEndian);
        } else if (tag === 0xB001) {
          numImages = ImageTools.readU32(mpfSeg, e + 8, bigEndian);
        }
      }
      if (mpeDataOff < 0) {
        Logger.info('WMHDR readHdrJpegParts: no MPEntry');
        return undefined;
      }
      const mpe: number = t0 + mpeDataOff;
      const entry0SizePos: number = mpe + 4;
      const entry1OffPos: number = mpe + 16 + 8;
      const entry1SizePos: number = mpe + 16 + 4;
      const srcPrimarySize: number = ImageTools.readU32(mpfSeg, entry0SizePos, bigEndian);
      const gainOffField: number = ImageTools.readU32(mpfSeg, entry1OffPos, bigEndian);
      const gainSizeField: number = ImageTools.readU32(mpfSeg, entry1SizePos, bigEndian);
      let gainPos: number = -1;
      if (srcPrimarySize > 4 && srcPrimarySize + 1 < f.length &&
        f[srcPrimarySize] === 0xFF && f[srcPrimarySize + 1] === 0xD8) {
        gainPos = srcPrimarySize;
      }
      if (gainPos < 0) {
        let e: number = sosPos;
        while (e + 1 < f.length) {
          if (f[e] === 0xFF && f[e + 1] === 0xD9) {
            break;
          }
          e++;
        }
        gainPos = e + 2;
      }
      if (gainPos < 0 || gainPos + 1 >= f.length || f[gainPos] !== 0xFF || f[gainPos + 1] !== 0xD8) {
        Logger.info(`WMHDR readHdrJpegParts: gainmap not found gainPos=${gainPos}`);
        return undefined;
      }
      let gainLen: number = gainSizeField;
      if (gainLen <= 0 || gainPos + gainLen > f.length) {
        gainLen = f.length - gainPos;
      }
      const gainEnd: number = gainPos + gainLen;
      if (gainEnd + 8 < f.length) {
        let hx: string = '';
        for (let i = 0; i < 8; i++) {
          hx += f[gainEnd + i].toString(16).padStart(2, '0') + ' ';
        }
        Logger.info(`WMHDR trailing: at ${gainEnd} remain=${f.length - gainEnd} bytes=${hx} ` +
          `ftyp=${ImageTools.asciiEq(f, gainEnd + 4, 'ftyp')}`);
      }
      const parts: HdrJpegParts = new HdrJpegParts();
      parts.isoSeg = isoSeg;
      parts.mpfSeg = mpfSeg;
      parts.t35Seg = t35Seg;
      parts.gainmap = f.slice(gainPos, gainPos + gainLen);
      parts.entry0SizePos = entry0SizePos;
      parts.entry1OffPos = entry1OffPos;
      parts.entry1SizePos = entry1SizePos;
      parts.bigEndian = bigEndian;
      parts.offsetBasis = gainPos - gainOffField;
      Logger.info(`WMHDR parts: primary=${srcPrimarySize} gainPos=${gainPos} gainLen=${gainLen} ` +
        `offField=${gainOffField} basis=${parts.offsetBasis} num=${numImages} be=${bigEndian} iso=${isoSeg.length} ` +
        `mpf=${mpfSeg.length} t35=${t35Seg.length}`);
      return parts;
    } catch (err) {
      Logger.error(`ImageTools readHdrJpegParts failed: ${JSON.stringify(err)}`);
      return undefined;
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  // 按最终版式重合成增益图：黑底（零增益）+ 照片矩形内映射原增益图，其余区域（白框/参数条）无 HDR 提升
  // rect 坐标为输出图像素坐标（与导出 pm 同单位）
  static async recomposeGainmap(parts: HdrJpegParts, outW: number, outH: number,
    rx: number, ry: number, rw: number, rh: number): Promise<boolean> {
    let srcSource: image.ImageSource | undefined = undefined;
    let srcPm: image.PixelMap | undefined = undefined;
    let tgtPm: image.PixelMap | undefined = undefined;
    try {
      if (parts.gainmap.length === 0 || outW <= 0 || outH <= 0 || rw <= 0 || rh <= 0) {
        return false;
      }
      srcSource = image.createImageSource(parts.gainmap.buffer);
      const decOpts: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      srcPm = await srcSource.createPixelMap(decOpts);
      const srcInfo: image.ImageInfo = await srcPm.getImageInfo();
      const gw: number = srcInfo.size.width;
      const gh: number = srcInfo.size.height;
      if (gw <= 0 || gh <= 0) {
        return false;
      }
      const srcBuf: ArrayBuffer = new ArrayBuffer(gw * gh * 4);
      await srcPm.readPixelsToBuffer(srcBuf);
      const src8: Uint8Array = new Uint8Array(srcBuf);
      // 目标分辨率：沿用源增益图相对照片的分辨率，长边不超过 1600
      const tsRaw: number = gw / rw;
      const capTs: number = 1600 / Math.max(outW, outH);
      const ts: number = Math.min(tsRaw, Math.max(capTs, 1 / 64));
      const tw: number = Math.max(2, Math.round(outW * ts));
      const th: number = Math.max(2, Math.round(outH * ts));
      const rxs: number = rx * ts;
      const rys: number = ry * ts;
      const rws: number = Math.max(1, rw * ts);
      const rhs: number = Math.max(1, rh * ts);
      const tgt: Uint8Array = new Uint8Array(tw * th * 4);
      for (let y = 0; y < th; y++) {
        const inY: boolean = y >= rys && y < rys + rhs;
        const sy: number = inY ?
          Math.min(gh - 1, Math.max(0, Math.round((y - rys) * gh / rhs))) : 0;
        for (let x = 0; x < tw; x++) {
          const o: number = (y * tw + x) * 4;
          if (inY && x >= rxs && x < rxs + rws) {
            const sx: number = Math.min(gw - 1, Math.max(0, Math.round((x - rxs) * gw / rws)));
            const v: number = src8[(sy * gw + sx) * 4];
            tgt[o] = v;
            tgt[o + 1] = v;
            tgt[o + 2] = v;
          } else {
            tgt[o] = 0;
            tgt[o + 1] = 0;
            tgt[o + 2] = 0;
          }
          tgt[o + 3] = 255;
        }
      }
      const initOpts: image.InitializationOptions = {
        size: { width: tw, height: th },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        srcPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      tgtPm = await image.createPixelMap(tgt.buffer, initOpts);
      const packer: image.ImagePacker = image.createImagePacker();
      const packed: ArrayBuffer = await packer.packToData(tgtPm, { format: 'image/jpeg', quality: 85 });
      packer.release();
      parts.gainmap = new Uint8Array(packed);
      Logger.info(`WMHDR recompose: src=${gw}x${gh} tgt=${tw}x${th} ` +
        `rect=(${Math.round(rx)},${Math.round(ry)},${Math.round(rw)},${Math.round(rh)}) ` +
        `out=${Math.round(outW)}x${Math.round(outH)} newLen=${packed.byteLength}`);
      return true;
    } catch (err) {
      Logger.error(`WMHDR recompose failed: ${JSON.stringify(err)}`);
      return false;
    } finally {
      if (srcPm !== undefined) {
        srcPm.release();
      }
      if (tgtPm !== undefined) {
        tgtPm.release();
      }
      if (srcSource !== undefined) {
        srcSource.release();
      }
    }
  }

  static async saveHdrToGallery(context: common.UIAbilityContext, pm: image.PixelMap,
    parts: HdrJpegParts, exifSeg?: Uint8Array): Promise<boolean> {
    let file: fileIo.File | undefined = undefined;
    try {
      const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const uri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg');
      const packer: image.ImagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: 95
      };
      const data: ArrayBuffer = await packer.packToData(pm, packOpts);
      packer.release();
      let p: Uint8Array = new Uint8Array(data);
      // 继承原片 EXIF：插在打包主体 SOI 后，primaryLen 随之增长，MPF 偏移自动保持一致
      if (exifSeg !== undefined && exifSeg.length > 0 && p.length > 2 &&
        p[0] === 0xFF && p[1] === 0xD8) {
        p = ImageTools.insertSegmentAfterSoi(p, exifSeg);
        Logger.info(`WMEXIF inherit(hdr) exifLen=${exifSeg.length}`);
      }
      const primaryLen: number = p.length + parts.isoSeg.length + parts.mpfSeg.length + parts.t35Seg.length;
      // MPF 偏移语义：相对于 MPF TIFF 头（MP Endian 字段）起点
      // OUT 布局：SOI(2) + isoSeg + mpfSeg(内含 8 字节头部后为 TIFF 头) + t35Seg + 打包主体 + gainmap
      const tiffStartOut: number = 2 + parts.isoSeg.length + 8;
      ImageTools.writeU32(parts.mpfSeg, parts.entry0SizePos, primaryLen, parts.bigEndian);
      ImageTools.writeU32(parts.mpfSeg, parts.entry1OffPos, primaryLen - tiffStartOut, parts.bigEndian);
      if (parts.entry1SizePos > 0) {
        ImageTools.writeU32(parts.mpfSeg, parts.entry1SizePos, parts.gainmap.length, parts.bigEndian);
      }
      const total: number = primaryLen + parts.gainmap.length;
      const out: Uint8Array = new Uint8Array(total);
      out.set(p.subarray(0, 2), 0);
      let off: number = 2;
      out.set(parts.isoSeg, off);
      off += parts.isoSeg.length;
      out.set(parts.mpfSeg, off);
      off += parts.mpfSeg.length;
      out.set(parts.t35Seg, off);
      off += parts.t35Seg.length;
      out.set(p.subarray(2), off);
      out.set(parts.gainmap, primaryLen);
      ImageTools.logJpegStructure('OUT', out);
      ImageTools.verifyMpfOffsets(out, primaryLen);
      const verify: RawExif | undefined = parseJpegExif(out);
      Logger.info(`WMEXIF hdr verify: make=[${verify === undefined ? 'NONE' : verify.make}] ` +
        `model=[${verify === undefined ? 'NONE' : verify.model}] iso=[${verify === undefined ? 'NONE' : verify.iso}] ` +
        `orient=${verify === undefined ? -1 : verify.orientation}`);
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, out.buffer);
      return true;
    } catch (err) {
      Logger.error(`ImageTools saveHdr failed: ${JSON.stringify(err)}`);
      return false;
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  // 以读者视角重解析 OUT：按 MPF 字段定位增益图，校验 FFD8 与长度
  static verifyMpfOffsets(out: Uint8Array, primaryLen: number): void {
    try {
      let pos: number = 2;
      while (pos + 4 <= out.length) {
        if (out[pos] !== 0xFF) {
          break;
        }
        const marker: number = out[pos + 1];
        if (marker === 0xDA || marker === 0xD9) {
          break;
        }
        const len: number = (out[pos + 2] << 8) | out[pos + 3];
        if (marker === 0xE2 && ImageTools.asciiEq(out, pos + 4, 'MPF')) {
          const t0: number = pos + 8;
          let bigEndian: boolean = true;
          if (out[t0] === 0x49 && out[t0 + 1] === 0x49) {
            bigEndian = false;
          }
          const ifd: number = t0 + ImageTools.readU32(out, t0 + 4, bigEndian);
          const cnt: number = ImageTools.readU16(out, ifd, bigEndian);
          let mpe: number = -1;
          for (let i = 0; i < cnt; i++) {
            const e: number = ifd + 2 + i * 12;
            if (ImageTools.readU16(out, e, bigEndian) === 0xB002) {
              mpe = t0 + ImageTools.readU32(out, e + 8, bigEndian);
            }
          }
          if (mpe < 0) {
            Logger.error('WMHDR selfcheck FAIL: no MPEntry');
            return;
          }
          const e0Size: number = ImageTools.readU32(out, mpe + 4, bigEndian);
          const e1Off: number = ImageTools.readU32(out, mpe + 16 + 8, bigEndian);
          const e1Size: number = ImageTools.readU32(out, mpe + 16 + 4, bigEndian);
          const gainPos: number = t0 + e1Off;
          const ok: boolean = out[gainPos] === 0xFF && out[gainPos + 1] === 0xD8 &&
            gainPos === primaryLen && e0Size === primaryLen;
          Logger.info(`WMHDR selfcheck ${ok ? 'PASS' : 'FAIL'}: tiffStart=${t0} ` +
            `e0size=${e0Size} e1off=${e1Off} e1size=${e1Size} gainPos=${gainPos} ` +
            `primaryLen=${primaryLen} ffd8=${out[gainPos] === 0xFF && out[gainPos + 1] === 0xD8}`);
          return;
        }
        pos += 2 + len;
      }
      Logger.error('WMHDR selfcheck FAIL: MPF seg not found in OUT');
    } catch (err) {
      Logger.error(`WMHDR selfcheck error: ${JSON.stringify(err)}`);
    }
  }

  static async saveToGallery(context: common.UIAbilityContext, pm: image.PixelMap,
    usePng: boolean, exifSeg?: Uint8Array): Promise<boolean> {
    let file: fileIo.File | undefined = undefined;
    try {
      const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const ext: string = usePng ? 'png' : 'jpg';
      const uri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, ext);
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      const packer: image.ImagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: usePng ? 'image/png' : 'image/jpeg',
        quality: 95
      };
      const data: ArrayBuffer = await packer.packToData(pm, packOpts);
      // JPEG 输出继承原片 EXIF（PNG 段结构与 EXIF APP1 不兼容，跳过）
      let merged: Uint8Array | undefined = undefined;
      if (!usePng && exifSeg !== undefined && exifSeg.length > 0) {
        const src: Uint8Array = new Uint8Array(data);
        if (src.length > 2 && src[0] === 0xFF && src[1] === 0xD8) {
          merged = ImageTools.insertSegmentAfterSoi(src, exifSeg);
          Logger.info(`WMEXIF inherit(std) exifLen=${exifSeg.length}`);
          const verify: RawExif | undefined = parseJpegExif(merged);
          Logger.info(`WMEXIF std verify: make=[${verify === undefined ? 'NONE' : verify.make}] ` +
            `model=[${verify === undefined ? 'NONE' : verify.model}] iso=[${verify === undefined ? 'NONE' : verify.iso}] ` +
            `orient=${verify === undefined ? -1 : verify.orientation}`);
        }
      }
      if (merged !== undefined) {
        fileIo.writeSync(file.fd, merged.buffer);
      } else {
        fileIo.writeSync(file.fd, data);
      }
      packer.release();
      return true;
    } catch (err) {
      Logger.error(`ImageTools save failed: ${JSON.stringify(err)}`);
      return false;
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  // 导入个人 Logo：解码所选图 → 判墨（有透明通道按 alpha，无透明按亮度，自动适应白底黑标/黑底白标）
  // → 裁剪空白边 → 生成黑/白单色变体（与品牌 Logo 同构）+ 原色彩色版（仅透明源）→ 存 PNG 到沙箱 files/logo/
  static async importPersonalLogo(context: common.UIAbilityContext,
    uri: string): Promise<PersonalLogoResult | undefined> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const source: image.ImageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      const scale: number = Math.min(1, 512 / Math.max(info.size.width, info.size.height));
      const w: number = Math.max(1, Math.round(info.size.width * scale));
      const h: number = Math.max(1, Math.round(info.size.height * scale));
      const pm: image.PixelMap = await source.createPixelMap({
        desiredSize: { width: w, height: h },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      await source.release();
      const buf: ArrayBuffer = new ArrayBuffer(w * h * 4);
      const area: image.PositionArea = {
        pixels: buf,
        offset: 0,
        stride: w * 4,
        region: { x: 0, y: 0, size: { width: w, height: h } }
      };
      await pm.readPixels(area);
      await pm.release();
      const dv: DataView = new DataView(buf);
      const n: number = w * h;
      // 透明源判定：超过 2% 像素带透明即按 alpha 作墨
      let transparent: number = 0;
      for (let i = 0; i < n; i++) {
        if (dv.getUint8(i * 4 + 3) < 250) {
          transparent++;
        }
      }
      const hasAlpha: boolean = transparent > n * 0.02;
      // 不透明源：按边界平均亮度判定墨色极性（边界暗 → 亮为墨，即黑底白标）
      let lightInk: boolean = false;
      if (!hasAlpha) {
        let borderLuma: number = 0;
        let bc: number = 0;
        for (let x = 0; x < w; x++) {
          let o: number = x * 4;
          borderLuma += 0.299 * dv.getUint8(o + 2) + 0.587 * dv.getUint8(o + 1) + 0.114 * dv.getUint8(o);
          bc++;
          o = ((h - 1) * w + x) * 4;
          borderLuma += 0.299 * dv.getUint8(o + 2) + 0.587 * dv.getUint8(o + 1) + 0.114 * dv.getUint8(o);
          bc++;
        }
        for (let y = 0; y < h; y++) {
          let o: number = y * w * 4;
          borderLuma += 0.299 * dv.getUint8(o + 2) + 0.587 * dv.getUint8(o + 1) + 0.114 * dv.getUint8(o);
          bc++;
          o = (y * w + w - 1) * 4;
          borderLuma += 0.299 * dv.getUint8(o + 2) + 0.587 * dv.getUint8(o + 1) + 0.114 * dv.getUint8(o);
          bc++;
        }
        lightInk = borderLuma / bc < 110;
      }
      // 逐像素算墨量并求包围盒
      const ink: Uint8Array = new Uint8Array(n);
      let minX: number = w;
      let minY: number = h;
      let maxX: number = -1;
      let maxY: number = -1;
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          const o: number = (y * w + x) * 4;
          let a: number;
          if (hasAlpha) {
            a = dv.getUint8(o + 3);
          } else {
            const l: number = 0.299 * dv.getUint8(o + 2) + 0.587 * dv.getUint8(o + 1) + 0.114 * dv.getUint8(o);
            a = Math.round(lightInk ? l : 255 - l);
          }
          ink[y * w + x] = a;
          if (a > 16) {
            if (x < minX) {
              minX = x;
            }
            if (y < minY) {
              minY = y;
            }
            if (x > maxX) {
              maxX = x;
            }
            if (y > maxY) {
              maxY = y;
            }
          }
        }
      }
      if (maxX < 0 || maxY < 0) {
        Logger.error('WMLOGO personal import: no ink found');
        return undefined;
      }
      const bw: number = maxX - minX + 1;
      const bh: number = maxY - minY + 1;
      const aspect: number = bw / bh;
      // 生成黑/白/彩色三个裁剪缓冲（字节序 BGRA）
      const size: number = bw * bh * 4;
      const bufB: ArrayBuffer = new ArrayBuffer(size);
      const bufW: ArrayBuffer = new ArrayBuffer(size);
      const bufC: ArrayBuffer = new ArrayBuffer(size);
      const bB: Uint8Array = new Uint8Array(bufB);
      const bW: Uint8Array = new Uint8Array(bufW);
      const bC: Uint8Array = new Uint8Array(bufC);
      for (let y = 0; y < bh; y++) {
        for (let x = 0; x < bw; x++) {
          const si: number = ((minY + y) * w + (minX + x)) * 4;
          const di: number = (y * bw + x) * 4;
          const a: number = ink[(minY + y) * w + (minX + x)];
          bB[di] = 0;
          bB[di + 1] = 0;
          bB[di + 2] = 0;
          bB[di + 3] = a;
          bW[di] = 255;
          bW[di + 1] = 255;
          bW[di + 2] = 255;
          bW[di + 3] = a;
          bC[di] = dv.getUint8(si);
          bC[di + 1] = dv.getUint8(si + 1);
          bC[di + 2] = dv.getUint8(si + 2);
          bC[di + 3] = a;
        }
      }
      // 写入沙箱 files/logo/
      const dir: string = `${context.filesDir}/logo`;
      try {
        fileIo.mkdirSync(dir);
      } catch (err) {
        // 已存在
      }
      const okB: boolean = await ImageTools.saveLogoPng(bufB, bw, bh, `${dir}/personal-b.png`);
      const okW: boolean = await ImageTools.saveLogoPng(bufW, bw, bh, `${dir}/personal-w.png`);
      let hasColor: boolean = false;
      if (hasAlpha) {
        hasColor = await ImageTools.saveLogoPng(bufC, bw, bh, `${dir}/personal-img.png`);
      } else {
        try {
          fileIo.unlinkSync(`${dir}/personal-img.png`);
        } catch (err) {
          // 无旧文件
        }
      }
      if (!okB || !okW) {
        Logger.error('WMLOGO personal import: save variants failed');
        return undefined;
      }
      const res: PersonalLogoResult = new PersonalLogoResult();
      res.aspect = aspect;
      res.hasColor = hasColor;
      Logger.info(`WMLOGO personal import ok: src=${info.size.width}x${info.size.height} ` +
        `trimmed=${bw}x${bh} aspect=${aspect.toFixed(2)} alpha=${hasAlpha} color=${hasColor}`);
      return res;
    } catch (err) {
      Logger.error(`WMLOGO personal import failed: ${JSON.stringify(err)}`);
      return undefined;
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  private static async saveLogoPng(buf: ArrayBuffer, w: number, h: number, path: string): Promise<boolean> {
    let f: fileIo.File | undefined = undefined;
    let pm: image.PixelMap | undefined = undefined;
    try {
      const opts: image.InitializationOptions = {
        size: { width: w, height: h },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        srcPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      pm = await image.createPixelMap(buf, opts);
      const packer: image.ImagePacker = image.createImagePacker();
      const data: ArrayBuffer = await packer.packToData(pm, { format: 'image/png', quality: 100 });
      packer.release();
      f = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, data);
      return true;
    } catch (err) {
      Logger.error(`WMLOGO save png failed path=${path} err=${JSON.stringify(err)}`);
      return false;
    } finally {
      if (pm !== undefined) {
        pm.release();
      }
      if (f !== undefined) {
        fileIo.closeSync(f);
      }
    }
  }
}
