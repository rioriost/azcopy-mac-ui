#!/usr/bin/env node
// Install optional test tools in .build/compatibility-tools; nothing is bundled in the app.
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdtemp, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const require = createRequire(join(root, '.build/compatibility-tools/package.json'));
const { BlobServiceClient, StorageSharedKeyCredential, generateAccountSASQueryParameters,
    AccountSASPermissions, AccountSASServices, AccountSASResourceTypes, SASProtocol } = require('@azure/storage-blob');
const executable = resolve(process.argv[2] ?? '/opt/homebrew/bin/azcopy');
await access(executable);
const temp = await mkdtemp(join(tmpdir(), 'azcopy-azurite-'));
const reservation = createServer();
await new Promise((ok, fail) => { reservation.once('error', fail); reservation.listen(0, '127.0.0.1', ok); });
const port = reservation.address().port;
await new Promise(ok => reservation.close(ok));
const key = randomBytes(32).toString('base64');
const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('AZCOPY_') && !name.startsWith('AZURITE_')));
const emulator = spawn(process.execPath, [require.resolve('azurite/dist/src/blob/main.js'),
    '--blobHost', '127.0.0.1', '--blobPort', String(port), '--location', temp,
    '--silent', '--skipApiVersionCheck'], {
    cwd: root, env: { ...env, AZURITE_ACCOUNTS: `azcopytest:${key}` }, stdio: 'ignore'
});
const emulatorExit = new Promise(ok => { emulator.once('exit', ok); emulator.once('error', ok); });
let tests;
function stop() { tests?.kill('SIGTERM'); emulator.kill('SIGTERM'); }
process.once('SIGINT', stop);
process.once('SIGTERM', stop);
try {
    const credential = new StorageSharedKeyCredential('azcopytest', key);
    const base = `http://127.0.0.1:${port}/azcopytest`;
    const service = new BlobServiceClient(base, credential, { retryOptions: { maxTries: 1 } });
    let ready = false;
    for (let attempt = 0; attempt < 40; attempt++) {
        if (emulator.exitCode !== null) throw new Error('Azurite exited before becoming ready');
        try { await service.getContainerClient('compat').create(); ready = true; break; }
        catch { await delay(250); }
    }
    if (!ready) throw new Error('Local Azurite did not become ready');
    const sas = generateAccountSASQueryParameters({
        services: AccountSASServices.parse('b').toString(),
        resourceTypes: AccountSASResourceTypes.parse('sco').toString(),
        permissions: AccountSASPermissions.parse('rwdlacuptf'),
        protocol: SASProtocol.HttpsAndHttp,
        startsOn: new Date(Date.now() - 60_000), expiresOn: new Date(Date.now() + 30 * 60_000)
    }, credential).toString();
    console.log(`Local fixture: Azurite ${require('azurite/package.json').version}; disposable Blob storage`);
    tests = spawn('swift', ['test', '--filter', 'AzCopyCompatibilityTests'], {
        cwd: root, env: { ...env, AZCOPY_TEST_EXECUTABLE: executable, AZCOPY_TEST_BLOB_URL: `${base}/compat?${sas}` },
        stdio: 'inherit'
    });
    process.exitCode = await new Promise((ok, fail) => { tests.once('exit', code => ok(code ?? 1)); tests.once('error', fail); });
} finally {
    stop();
    await emulatorExit;
    await rm(temp, { recursive: true, force: true });
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
}
