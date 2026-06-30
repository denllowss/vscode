const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = 8080;
const CUSTOM_PASSWORD = 'denji#123';

console.log('='.repeat(60));
console.log('🚀 VSCode Server dengan Cloudflare Tunnel');
console.log('='.repeat(60));
console.log();

// Fungsi untuk set password custom
function setCustomPassword() {
  const configDir = path.join(os.homedir(), '.config', 'code-server');
  const configPath = path.join(configDir, 'config.yaml');
  
  // Buat direktori jika belum ada
  if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true });
  }
  
  // Buat config dengan password custom
  const config = `bind-addr: 127.0.0.1:${PORT}
auth: password
password: ${CUSTOM_PASSWORD}
cert: false
`;
  
  fs.writeFileSync(configPath, config);
  console.log('✅ Password custom telah di-set!');
}

// Set password sebelum start
setCustomPassword();

// Jalankan code-server
console.log('📦 Memulai Code-Server...');
const codeServer = spawn('code-server', [
  '--bind-addr', `127.0.0.1:${PORT}`,
  '--auth', 'password',
  '--disable-telemetry',
  '--disable-update-check'
], {
  stdio: 'pipe',
  shell: true
});

let serverReady = false;

codeServer.stdout.on('data', (data) => {
  const output = data.toString();
  
  // Deteksi server sudah siap
  if (output.includes('HTTP server listening') && !serverReady) {
    serverReady = true;
    console.log('✅ Code-Server siap di port', PORT);
    console.log('🔑 Password:', CUSTOM_PASSWORD);
    console.log();
  }
  
  // Tampilkan error jika ada
  if (output.includes('error') || output.includes('Error')) {
    console.log('❌', output);
  }
});

codeServer.stderr.on('data', (data) => {
  const output = data.toString();
  // Filter log yang tidak penting
  if (!output.includes('Using user-data-dir') && 
      !output.includes('Using config file')) {
    console.log('⚠️', output);
  }
});

codeServer.on('error', (error) => {
  console.error('❌ Error menjalankan code-server:', error.message);
  console.log('\n💡 Pastikan code-server sudah terinstall!');
  console.log('Install dengan: curl -fsSL https://code-server.dev/install.sh | sh');
  process.exit(1);
});

// Tunggu server siap, lalu jalankan cloudflared
setTimeout(() => {
  console.log('🌐 Membuat Cloudflare Tunnel...');
  console.log('⏳ Mohon tunggu...\n');
  
  const tunnel = spawn('cloudflared', [
    'tunnel',
    '--url', `http://localhost:${PORT}`,
    '--no-autoupdate'
  ], {
    stdio: 'pipe',
    shell: true
  });

  let tunnelUrl = null;

  tunnel.stdout.on('data', (data) => {
    const output = data.toString();
    
    // Cari URL tunnel
    const match = output.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
    if (match && !tunnelUrl) {
      tunnelUrl = match[0];
      
      console.log('\n' + '='.repeat(60));
      console.log('✅ VSCode Server SIAP DIGUNAKAN!');
      console.log('='.repeat(60));
      console.log('🌍 URL Publik  :', tunnelUrl);
      console.log('🔑 Password    :', CUSTOM_PASSWORD);
      console.log('👤 Username    : (tidak perlu, langsung password saja)');
      console.log('📁 Working Dir :', process.cwd());
      console.log('='.repeat(60));
      console.log('\n💡 Tips:');
      console.log('   - Buka URL di browser');
      console.log('   - Masukkan password: denji#123');
      console.log('   - Link AKTIF selama program berjalan');
      console.log('   - Tekan CTRL+C untuk menghentikan\n');
    }
    
    // Tampilkan log penting
    if (output.includes('error') || output.includes('failed')) {
      console.log('❌', output);
    }
  });

  tunnel.stderr.on('data', (data) => {
    const output = data.toString();
    
    // Filter log cloudflared yang tidak penting
    if (!output.includes('INFO') && 
        !output.includes('Registered tunnel') &&
        !output.includes('Connection registered') &&
        !output.includes('Metrics server')) {
      console.log(output);
    }
  });

  tunnel.on('error', (error) => {
    console.error('\n❌ Error menjalankan cloudflared:', error.message);
    console.log('\n💡 Install cloudflared:');
    console.log('\nUbuntu/Debian:');
    console.log('  wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb');
    console.log('  sudo dpkg -i cloudflared-linux-amd64.deb');
    console.log('\nCentOS/RHEL:');
    console.log('  wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.rpm');
    console.log('  sudo rpm -i cloudflared-linux-amd64.rpm');
    console.log('\nWindows:');
    console.log('  winget install Cloudflare.cloudflared');
    console.log('\nMacOS:');
    console.log('  brew install cloudflared\n');
    
    codeServer.kill();
    process.exit(1);
  });

  tunnel.on('close', (code) => {
    console.log('\n⚠️  Cloudflare Tunnel ditutup dengan kode:', code);
    codeServer.kill();
    process.exit(code);
  });

}, 5000);

// Handle termination
process.on('SIGINT', () => {
  console.log('\n\n⏹️  Menghentikan server...');
  console.log('👋 Terima kasih!\n');
  codeServer.kill();
  process.exit(0);
});

process.on('SIGTERM', () => {
  codeServer.kill();
  process.exit(0);
});

// Handle error yang tidak tertangkap
process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error.message);
  codeServer.kill();
  process.exit(1);
});
