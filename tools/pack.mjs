// Pakowanie wydania dla strony: node tools/pack.mjs <folder public/wow strony>
// Tworzy: addon.json (wersja + pliki addonu, z tego korzysta instalator i uploader),
// Ekipa.zip (reczna instalacja), install.ps1, uploader.ps1, uninstall.ps1.
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = process.argv[2];
if (!out) {
  console.error("Uzycie: node tools/pack.mjs ../ekipa-challange/public/wow");
  process.exit(1);
}
mkdirSync(out, { recursive: true });

const addonDir = join(root, "addon", "Ekipa");
const files = {};
for (const name of readdirSync(addonDir).sort()) {
  const text = readFileSync(join(addonDir, name), "utf8").replace(/\r\n/g, "\n");
  if (/[^\x00-\x7f]/.test(text)) throw new Error(`${name}: tylko ASCII (czcionki WoW i PowerShell 5.1)`);
  files[name] = text;
}
const version = /^## Version:\s*(\S+)/m.exec(files["Ekipa.toc"])?.[1];
const uploader = readFileSync(join(root, "uploader", "uploader.ps1"), "utf8");
const uploaderVersion = /\$UploaderVersion = '([^']+)'/.exec(uploader)?.[1];
if (!version || !uploaderVersion) throw new Error("Brak wersji addonu albo uploadera");
for (const f of ["uploader.ps1", "uninstall.ps1"]) {
  const t = readFileSync(join(root, "uploader", f), "utf8");
  if (/[^\x00-\x7f]/.test(t)) throw new Error(`${f}: tylko ASCII`);
}

writeFileSync(join(out, "addon.json"), JSON.stringify({ version, uploaderVersion, files }));
for (const f of ["install.ps1", "uploader.ps1", "uninstall.ps1"]) {
  writeFileSync(join(out, f), readFileSync(join(root, "uploader", f), "utf8").replace(/\r?\n/g, "\r\n"));
}

// zip bez kompresji (folder Ekipa/ gotowy do wrzucenia do Interface\AddOns)
const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const parts = [];
const central = [];
let offset = 0;
for (const [name, text] of Object.entries(files)) {
  const data = Buffer.from(text.replace(/\n/g, "\r\n"));
  const fname = Buffer.from(`Ekipa/${name}`);
  const crc = crc32(data);
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(10, 4);
  local.writeUInt32LE(crc, 14);
  local.writeUInt32LE(data.length, 18);
  local.writeUInt32LE(data.length, 22);
  local.writeUInt16LE(fname.length, 26);
  parts.push(local, fname, data);
  const cd = Buffer.alloc(46);
  cd.writeUInt32LE(0x02014b50, 0);
  cd.writeUInt16LE(20, 4);
  cd.writeUInt16LE(10, 6);
  cd.writeUInt32LE(crc, 16);
  cd.writeUInt32LE(data.length, 20);
  cd.writeUInt32LE(data.length, 24);
  cd.writeUInt16LE(fname.length, 28);
  cd.writeUInt32LE(offset, 42);
  central.push(cd, fname);
  offset += local.length + fname.length + data.length;
}
const cdBuf = Buffer.concat(central);
const end = Buffer.alloc(22);
end.writeUInt32LE(0x06054b50, 0);
end.writeUInt16LE(Object.keys(files).length, 8);
end.writeUInt16LE(Object.keys(files).length, 10);
end.writeUInt32LE(cdBuf.length, 12);
end.writeUInt32LE(offset, 16);
writeFileSync(join(out, "Ekipa.zip"), Buffer.concat([...parts, cdBuf, end]));

console.log(`addon ${version}, uploader ${uploaderVersion} -> ${out}`);
