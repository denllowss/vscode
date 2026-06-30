const { spawn, execSync } = require('child_process');

const PORT = 8080;
const MAX_RETRIES = 5;
let retryCount = 0;
let tunnelProcess = null;

console.log('🚀 Memulai VSCode Server dengan Cloudflare Tunnel...\n');

function checkConnectivity() {
  try {
    execSync('curl -s -m 5 -o /dev/null -w "%{http_code}" https://api.trycloudflare.com', { stdio: 'pipe' });
    return true;
  } catch (e) {
    return false;
  }
}

const codeServer = spawn('code-server', [
  '--bind-addr', `127.0.0.1:${PORT}`,
  '--auth', 'none',
  '--disable-telemetry'
], { stdio: 'pipe', shell: true });

codeServer.stdout.on('data', (data) => console.log(data.toString()));
codeServer.stderr.on('data', (data) => console.log(data.toString()));

setTimeout(() => {
  startTunnel();
}, 3000);

function startTunnel() {
  console.log(`\n🌐 Membuat Cloudflare Tunnel... (percobaan ${retryCount + 1}/${MAX_RETRIES})\n`);

  if (!checkConnectivity()) {
    console.log('⚠️  Tidak bisa menjangkau api.trycloudflare.com. Cek koneksi/DNS/firewall.');
  }

  tunnelProcess = spawn('cloudflared', [
    'tunnel',
    '--url', `http://localhost:${PORT}`,
    '--retries', '10',
    '--protocol', 'http2'   // http2 sering lebih stabil daripada quic di jaringan terbatas
  ], { stdio: 'pipe', shell: true });

  let urlFound = false;

  tunnelProcess.stdout.on('data', (data) => {
    const output = data.toString();
    console.log(output);
    const match = output.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
    if (match) {
      urlFound = true;
      console.log('\n✅ VSCode Server siap!');
      console.log('🌍 URL Publik:', match[0]);
      console.log('📌 Link ini AKTIF selama server berjalan\n');
    }
  });

  tunnelProcess.stderr.on('data', (data) => {
    const output = data.toString();
    console.log(output);
    const match = output.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
    if (match) {
      urlFound = true;
      console.log('\n✅ VSCode Server siap!');
      console.log('🌍 URL Publik:', match[0]);
    }
  });

  tunnelProcess.on('error', (error) => {
    console.error('❌ Error tunnel:', error.message);
    console.log('\n💡 Install cloudflared:');
    console.log('Ubuntu/Debian: wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && sudo dpkg -i cloudflared-linux-amd64.deb');
    console.log('Windows: winget install Cloudflare.cloudflared');
  });

  tunnelProcess.on('exit', (code) => {
    if (!urlFound && code !== 0) {
      retryCount++;
      console.log(`\n⚠️  Cloudflare Tunnel ditutup dengan kode: ${code}`);
      if (retryCount < MAX_RETRIES) {
        const delay = Math.min(2000 * retryCount, 10000);
        console.log(`🔁 Mencoba lagi dalam ${delay / 1000} detik...\n`);
        setTimeout(startTunnel, delay);
      } else {
        console.log('\n❌ Gagal membuat tunnel setelah beberapa percobaan.');
        console.log('Kemungkinan penyebab:');
        console.log('  1. Outbound HTTPS ke api.trycloudflare.com diblokir firewall/jaringan container');
        console.log('  2. DNS tidak bisa resolve trycloudflare.com (coba: nslookup api.trycloudflare.com)');
        console.log('  3. Coba alternatif tunnel: localtunnel (npx localtunnel --port 8080) atau ngrok');
      }
    }
  });
}

process.on('SIGINT', () => {
  console.log('\n⏹️  Menghentikan server...');
  if (tunnelProcess) tunnelProcess.kill();
  codeServer.kill();
  process.exit();
});
