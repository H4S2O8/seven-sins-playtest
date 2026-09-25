#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const https = require('node:https');
const zlib = require('node:zlib');
const { Transform, pipeline } = require('node:stream');
const { promisify } = require('node:util');
const pipelineAsync = promisify(pipeline);

const VERSION = '4.7.stable';
const ARCHIVE_SIZE = 1279207690;
const ARCHIVE_SHA256 = '9714459dc071907c0f3d5f17d608faf69e7cda21331fc5d39c4503ffa4e99eec';
const ARCHIVE_URL = 'https://github.com/godotengine/godot-builds/releases/download/4.7-stable/Godot_v4.7-stable_export_templates.tpz';
const TARGET_DIR = 'C:/Users/27654/Documents/Codex/2026-08-14/referenced-chatgpt-conversation-this-is-an/game/tools/godot-4.7/editor_data/export_templates/4.7.stable';
const REQUIRED_NAMES = ['web_release.zip', 'web_debug.zip', 'version.txt'];
const SINGLE_THREAD_NAMES = ['web_nothreads_release.zip', 'web_nothreads_debug.zip'];
const ARCHIVE_ENTRY_NAMES = [...REQUIRED_NAMES, ...SINGLE_THREAD_NAMES];
const REDIRECT_CODES = new Set([301, 302, 303, 307, 308]);

function request(url, range, redirects = 0) {
	return new Promise((resolve, reject) => {
		if (redirects > 8) return reject(new Error('Too many HTTP redirects'));
		const headers = { 'User-Agent': 'sin-squad-web-template-fetch/1.0', 'Accept-Encoding': 'identity' };
		if (range) headers.Range = `bytes=${range.start}-${range.end}`;
		const req = https.get(url, { headers, timeout: 30000 }, (res) => {
			if (REDIRECT_CODES.has(res.statusCode)) {
				const location = res.headers.location;
				res.resume();
				if (!location) return reject(new Error(`HTTP ${res.statusCode} without Location`));
				return resolve(request(new URL(location, url).toString(), range, redirects + 1));
			}
			if (range) {
				const expected = `bytes ${range.start}-${range.end}/${ARCHIVE_SIZE}`;
				if (res.statusCode !== 206 || res.headers['content-range'] !== expected) {
					res.destroy();
					return reject(new Error(`Range unavailable or invalid: HTTP ${res.statusCode}, Content-Range=${res.headers['content-range'] || '(missing)'}`));
				}
				const expectedLength = range.end - range.start + 1;
				if (res.headers['content-length'] !== String(expectedLength)) {
					res.destroy();
					return reject(new Error(`Range length mismatch: expected ${expectedLength}, got ${res.headers['content-length'] || '(missing)'}`));
				}
			}
			resolve(res);
		});
		req.on('timeout', () => req.destroy(new Error('HTTP request timed out')));
		req.on('error', reject);
	});
}

async function readRange(start, end) {
	const response = await request(ARCHIVE_URL, { start, end });
	const chunks = [];
	let length = 0;
	for await (const chunk of response) {
		length += chunk.length;
		chunks.push(chunk);
	}
	const expected = end - start + 1;
	if (length !== expected) throw new Error(`Received ${length} bytes for range ${start}-${end}, expected ${expected}`);
	return Buffer.concat(chunks, length);
}

function findDirectory(tail) {
	const eocdSignature = 0x06054b50;
	let eocd = -1;
	for (let i = tail.length - 22; i >= 0; i--) {
		if (tail.readUInt32LE(i) === eocdSignature && i + 22 + tail.readUInt16LE(i + 20) === tail.length) {
			eocd = i;
			break;
		}
	}
	if (eocd < 0) throw new Error('ZIP EOCD signature not found in final 65,557 bytes');
	const disk = tail.readUInt16LE(eocd + 4);
	const directoryDisk = tail.readUInt16LE(eocd + 6);
	const entriesOnDisk = tail.readUInt16LE(eocd + 8);
	const entryCount = tail.readUInt16LE(eocd + 10);
	const directorySize = tail.readUInt32LE(eocd + 12);
	const directoryOffset = tail.readUInt32LE(eocd + 16);
	if (disk !== 0 || directoryDisk !== 0 || entriesOnDisk !== entryCount) throw new Error('Multi-disk ZIP is not supported');
	if ([entriesOnDisk, entryCount].includes(0xffff) || [directorySize, directoryOffset].includes(0xffffffff)) {
		throw new Error('ZIP64 directory is not supported by this selective reader');
	}
	return { entryCount, directorySize, directoryOffset, eocdOffsetInTail: eocd };
}

function parseDirectory(buffer, expectedCount) {
	const entries = [];
	let offset = 0;
	while (offset < buffer.length) {
		if (buffer.length - offset < 46 || buffer.readUInt32LE(offset) !== 0x02014b50) {
			throw new Error(`Invalid central-directory signature at byte ${offset}`);
		}
		const flags = buffer.readUInt16LE(offset + 8);
		const method = buffer.readUInt16LE(offset + 10);
		const crc32 = buffer.readUInt32LE(offset + 16);
		const compressedSize = buffer.readUInt32LE(offset + 20);
		const uncompressedSize = buffer.readUInt32LE(offset + 24);
		const nameLength = buffer.readUInt16LE(offset + 28);
		const extraLength = buffer.readUInt16LE(offset + 30);
		const commentLength = buffer.readUInt16LE(offset + 32);
		const diskStart = buffer.readUInt16LE(offset + 34);
		const localHeaderOffset = buffer.readUInt32LE(offset + 42);
		const end = offset + 46 + nameLength + extraLength + commentLength;
		if (end > buffer.length) throw new Error('Truncated central-directory record');
		const rawName = buffer.subarray(offset + 46, offset + 46 + nameLength);
		const name = (flags & 0x0800 ? rawName.toString('utf8') : rawName.toString('utf8')).replace(/\\/g, '/');
		if (diskStart !== 0) throw new Error(`Entry is on another disk: ${name}`);
		if ([compressedSize, uncompressedSize, localHeaderOffset].includes(0xffffffff)) throw new Error(`ZIP64 entry not supported: ${name}`);
		entries.push({ name, flags, method, crc32, compressedSize, uncompressedSize, localHeaderOffset });
		offset = end;
	}
	if (offset !== buffer.length || entries.length !== expectedCount) throw new Error('Central-directory size/count mismatch');
	return entries;
}

function selectEntries(entries) {
	const selected = {};
	for (const basename of ARCHIVE_ENTRY_NAMES) {
		const matches = entries.filter((entry) => entry.name.split('/').at(-1) === basename && !entry.name.endsWith('/'));
		if (matches.length !== 1) throw new Error(`Expected one real archive entry named ${basename}; found ${matches.length}`);
		selected[basename] = matches[0];
	}
	return selected;
}

async function inspectArchive() {
	const tailLength = Math.min(65557, ARCHIVE_SIZE);
	const tail = await readRange(ARCHIVE_SIZE - tailLength, ARCHIVE_SIZE - 1);
	const directoryInfo = findDirectory(tail);
	const eocdAbsoluteOffset = ARCHIVE_SIZE - tailLength + directoryInfo.eocdOffsetInTail;
	if (directoryInfo.directoryOffset + directoryInfo.directorySize !== eocdAbsoluteOffset) throw new Error('Central-directory extent does not meet the EOCD record');
	const directory = await readRange(directoryInfo.directoryOffset, directoryInfo.directoryOffset + directoryInfo.directorySize - 1);
	const entries = parseDirectory(directory, directoryInfo.entryCount);
	const selected = selectEntries(entries);
	const versionResponse = await readEntryBuffer(selected['version.txt']);
	const versionText = versionResponse.toString('utf8').trim();
	if (versionText !== VERSION) throw new Error(`Template version entry says '${versionText}', expected '${VERSION}'`);
	for (const name of [...SINGLE_THREAD_NAMES, 'web_release.zip', 'web_debug.zip']) {
		const entry = selected[name];
		if (entry.method !== 8 && entry.method !== 0) throw new Error(`Unsupported ZIP compression method ${entry.method} for ${entry.name}`);
		if (entry.flags & 1) throw new Error(`Encrypted entry is not supported: ${entry.name}`);
	}
	return { directoryInfo, entries, selected, versionText };
}

function crcTable() {
	const table = new Uint32Array(256);
	for (let n = 0; n < 256; n++) {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		table[n] = c >>> 0;
	}
	return table;
}
const CRC_TABLE = crcTable();

function crcTransform(entry) {
	let crc = 0xffffffff;
	let size = 0;
	return {
		stream: new Transform({
			transform(chunk, _encoding, callback) {
				size += chunk.length;
				for (const byte of chunk) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
				callback(null, chunk);
			},
			flush(callback) {
				const actual = (crc ^ 0xffffffff) >>> 0;
				if (size !== entry.uncompressedSize) return callback(new Error(`Uncompressed size mismatch for ${entry.name}: ${size} != ${entry.uncompressedSize}`));
				if (actual !== entry.crc32) return callback(new Error(`CRC32 mismatch for ${entry.name}: ${actual.toString(16)} != ${entry.crc32.toString(16)}`));
				callback();
			},
		}),
	};
}

async function openEntryPayload(entry) {
	const local = await readRange(entry.localHeaderOffset, entry.localHeaderOffset + 29);
	if (local.readUInt32LE(0) !== 0x04034b50) throw new Error(`Invalid local ZIP signature for ${entry.name}`);
	const nameLength = local.readUInt16LE(26);
	const extraLength = local.readUInt16LE(28);
	const payloadStart = entry.localHeaderOffset + 30 + nameLength + extraLength;
	const payloadEnd = payloadStart + entry.compressedSize - 1;
	if (payloadEnd >= ARCHIVE_SIZE || payloadEnd < payloadStart) throw new Error(`Invalid compressed-data extent for ${entry.name}`);
	const localNameAndExtra = await readRange(entry.localHeaderOffset + 30, entry.localHeaderOffset + 30 + nameLength + extraLength - 1);
	const localName = localNameAndExtra.subarray(0, nameLength).toString('utf8').replace(/\\/g, '/');
	if (localName !== entry.name) throw new Error(`Local/central filename mismatch: ${localName} != ${entry.name}`);
	if (entry.method === 0) {
		return { stream: await request(ARCHIVE_URL, { start: payloadStart, end: payloadEnd }), isStored: true };
	}
	return { stream: await request(ARCHIVE_URL, { start: payloadStart, end: payloadEnd }), isStored: false };
}

async function readEntryBuffer(entry) {
	if (entry.uncompressedSize > 1024 * 1024) throw new Error(`Unexpectedly large metadata entry: ${entry.name}`);
	const payload = await openEntryPayload(entry);
	const chunks = [];
	const meter = crcTransform(entry).stream;
	const decoder = payload.isStored ? new Transform({ transform(chunk, _encoding, callback) { callback(null, chunk); } }) : zlib.createInflateRaw();
	await pipelineAsync(payload.stream, decoder, meter, new Transform({
		transform(chunk, _encoding, callback) { chunks.push(Buffer.from(chunk)); callback(); },
	}));
	return Buffer.concat(chunks);
}

async function hashFile(filePath) {
	const crypto = require('node:crypto');
	const hash = crypto.createHash('sha256');
	for await (const chunk of fs.createReadStream(filePath)) hash.update(chunk);
	return hash.digest('hex');
}

async function extractEntry(entry, destination) {
	const payload = await openEntryPayload(entry);
	const tempPath = `${destination}.part-${process.pid}`;
	const meter = crcTransform(entry).stream;
	const decoder = payload.isStored ? new Transform({ transform(chunk, _encoding, callback) { callback(null, chunk); } }) : zlib.createInflateRaw();
	try {
		await pipelineAsync(payload.stream, decoder, meter, fs.createWriteStream(tempPath, { flags: 'wx' }));
		const handle = await fs.promises.open(tempPath, 'r');
		const signature = Buffer.alloc(4);
		await handle.read(signature, 0, 4, 0);
		await handle.close();
		if (entry.name.split('/').at(-1).endsWith('.zip') && signature.readUInt32LE(0) !== 0x04034b50) {
			throw new Error(`Extracted template is not a ZIP local-file stream: ${entry.name}`);
		}
		return { tempPath, sha256: await hashFile(tempPath) };
	} catch (error) {
		await fs.promises.rm(tempPath, { force: true });
		throw error;
	}
}

async function main() {
	const install = process.argv.includes('--install');
	const { directoryInfo, entries, selected, versionText } = await inspectArchive();
	console.log(`Source: ${ARCHIVE_URL}`);
	console.log(`Release: ${VERSION}; official TPZ size=${ARCHIVE_SIZE}; published SHA-256=${ARCHIVE_SHA256} (full package is not downloaded, so this digest cannot be recomputed locally).`);
	console.log(`HTTP Range supported: yes; ZIP entries=${entries.length}; central directory bytes=${directoryInfo.directorySize}; entry version=${versionText}`);
	for (const name of ARCHIVE_ENTRY_NAMES) {
		const entry = selected[name];
		console.log(`${name}: entry=${entry.name}; method=${entry.method}; compressed=${entry.compressedSize}; extracted=${entry.uncompressedSize}; CRC32=${entry.crc32.toString(16).padStart(8, '0')}`);
	}
	if (!install) {
		console.log('Read-only inspection only. Re-run with --install to write exactly the selected entries.');
		return;
	}

	const target = path.resolve(TARGET_DIR);
	const targetDrive = path.parse(target).root;
	const stat = fs.statfsSync(targetDrive);
	const available = Number(stat.bavail) * Number(stat.bsize);
	const missingNames = SINGLE_THREAD_NAMES.filter((name) => !fs.existsSync(path.join(target, name)));
	const requiredBytes = missingNames.reduce((sum, name) => sum + selected[name].uncompressedSize, 0);
	const reserveBytes = 256 * 1024 * 1024;
	console.log(`Install target: ${target}`);
	console.log(`Free bytes: ${available}; bytes to write: ${requiredBytes}; required reserve: ${reserveBytes}`);
	if (available < requiredBytes + reserveBytes) throw new Error('Insufficient free space; no template files were written');
	for (const name of SINGLE_THREAD_NAMES) {
		const existingPath = path.join(target, name);
		if (!fs.existsSync(existingPath)) continue;
		if (name === 'version.txt' && (await fs.promises.readFile(existingPath, 'utf8')).trim() === VERSION) continue;
		throw new Error(`Refusing to overwrite existing file: ${existingPath}`);
	}

	await fs.promises.mkdir(target, { recursive: true });
	const staged = [];
	try {
		for (const name of SINGLE_THREAD_NAMES) {
			if (fs.existsSync(path.join(target, name))) continue;
			const result = await extractEntry(selected[name], path.join(target, name));
			staged.push({ name, ...result });
		}
		for (const item of staged) {
			await fs.promises.rename(item.tempPath, path.join(target, item.name));
			console.log(`Installed ${item.name}; SHA-256=${item.sha256}`);
		}
	} catch (error) {
		for (const item of staged) await fs.promises.rm(item.tempPath, { force: true });
		throw error;
	}
	console.log(`Selective Web template install complete. No full TPZ was saved; ${SINGLE_THREAD_NAMES.length} single-thread entries passed CRC32 validation.`);
}

main().catch((error) => {
	console.error(`ERROR: ${error.message}`);
	process.exitCode = 1;
});
