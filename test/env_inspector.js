const fs = require('fs');
const cp = require('child_process');
const path = require('path');

console.log('=== 1. ANDROID SDK DISCOVERY ===');
const sdkPath = 'C:\\Users\\Abhis\\AppData\\Local\\Android\\Sdk';
if (fs.existsSync(sdkPath)) {
  console.log('Sdk exists at:', sdkPath);
  const items = fs.readdirSync(sdkPath);
  console.log('Sdk contents:', items.join(', '));
  
  const platformsPath = path.join(sdkPath, 'platforms');
  if (fs.existsSync(platformsPath)) {
    console.log('Platforms:', fs.readdirSync(platformsPath).join(', '));
  }
  
  const buildToolsPath = path.join(sdkPath, 'build-tools');
  if (fs.existsSync(buildToolsPath)) {
    console.log('Build tools:', fs.readdirSync(buildToolsPath).join(', '));
  }
  
  const licensesPath = path.join(sdkPath, 'licenses');
  if (fs.existsSync(licensesPath)) {
    console.log('Licenses:', fs.readdirSync(licensesPath).join(', '));
  } else {
    console.log('Licenses directory not found in SDK.');
  }
} else {
  console.log('Sdk path does not exist:', sdkPath);
}

console.log('\n=== 2. ADB & CONNECTED DEVICES ===');
const adb = 'C:\\Users\\Abhis\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe';
if (fs.existsSync(adb)) {
  try {
    const devices = cp.execSync(`"${adb}" devices -l`, { encoding: 'utf8' });
    console.log('ADB Devices:\n' + devices);
  } catch(e) {
    console.log('ADB error:', e.message);
  }
} else {
  console.log('adb.exe not found at:', adb);
}

console.log('\n=== 3. ANDROID EMULATOR / AVD CHECK ===');
const emulator = 'C:\\Users\\Abhis\\AppData\\Local\\Android\\Sdk\\emulator\\emulator.exe';
if (fs.existsSync(emulator)) {
  try {
    const avds = cp.execSync(`"${emulator}" -list-avds`, { encoding: 'utf8' });
    console.log('Configured AVDs:\n' + (avds.trim() ? avds : '(None configured)'));
  } catch(e) {
    console.log('Emulator query error:', e.message);
  }
} else {
  console.log('emulator.exe not found at:', emulator);
}

console.log('\n=== 4. JAVA / JDK VERSION ===');
try {
  const javaVer = cp.execSync('java -version 2>&1', { encoding: 'utf8' });
  console.log('Default Java:\n' + javaVer);
} catch(e) {
  console.log('Java error:', e.message);
}

const jdk21 = 'C:\\Program Files\\Java\\jdk-21\\bin\\java.exe';
if (fs.existsSync(jdk21)) {
  try {
    const jdkVer = cp.execSync(`"${jdk21}" -version 2>&1`, { encoding: 'utf8' });
    console.log('JDK 21:\n' + jdkVer);
  } catch(e) {}
}

console.log('\n=== 5. ANDROID STUDIO INSTALLATION ===');
const asPath = 'C:\\Program Files\\Android\\Android Studio';
if (fs.existsSync(asPath)) {
  console.log('Android Studio directory found at:', asPath);
  try {
    const contents = fs.readdirSync(asPath);
    console.log('Contents:', contents.join(', '));
    const jbrPath = path.join(asPath, 'jbr', 'bin', 'java.exe');
    if (fs.existsSync(jbrPath)) {
      console.log('Embedded JetBrains JBR found at:', jbrPath);
    }
  } catch(e) {}
}

console.log('\n=== 6. FLUTTER / DART SDK HUNT ===');
const potentialFlutterLocations = [
  'C:\\flutter',
  'C:\\src\\flutter',
  'C:\\dev\\flutter',
  'C:\\tools\\flutter',
  'D:\\flutter',
  'D:\\src\\flutter',
  'D:\\tools\\flutter',
  'C:\\Users\\Abhis\\flutter',
  'C:\\Users\\Abhis\\AppData\\Local\\Android\\flutter',
  'C:\\Users\\Abhis\\AppData\\Local\\flutter',
  'C:\\Users\\Abhis\\AppData\\Roaming\\flutter',
  'C:\\Users\\Abhis\\Downloads\\flutter',
  'C:\\Users\\Abhis\\scoop\\apps\\flutter\\current',
  'C:\\Program Files\\flutter'
];

let foundFlutter = null;
for (const loc of potentialFlutterLocations) {
  const bat = path.join(loc, 'bin', 'flutter.bat');
  if (fs.existsSync(bat)) {
    console.log('Found Flutter at:', bat);
    foundFlutter = bat;
    break;
  }
}
if (!foundFlutter) {
  console.log('Flutter binary not found in standard paths. Searching user Downloads / Documents...');
  const userFolders = ['C:\\Users\\Abhis\\Downloads', 'C:\\Users\\Abhis\\Documents', 'C:\\Users\\Abhis'];
  for (const uf of userFolders) {
    if (fs.existsSync(uf)) {
      try {
        const sub = fs.readdirSync(uf);
        for (const s of sub) {
          const testBat = path.join(uf, s, 'bin', 'flutter.bat');
          if (fs.existsSync(testBat)) {
            console.log('Found Flutter at:', testBat);
            foundFlutter = testBat;
            break;
          }
        }
      } catch(e) {}
    }
    if (foundFlutter) break;
  }
}
if (!foundFlutter) {
  console.log('Flutter SDK location: NOT FOUND in local filesystem search.');
}
