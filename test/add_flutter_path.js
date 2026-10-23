const cp = require('child_process');

try {
  const current = cp.execSync('reg query "HKCU\\Environment" /v Path', { encoding: 'utf8' });
  const lines = current.split('\n');
  let currentVal = '';
  for (const line of lines) {
    if (line.includes('Path')) {
      const parts = line.trim().split(/\s{2,}/);
      if (parts.length >= 3) {
        currentVal = parts[2];
      }
    }
  }

  if (currentVal && !currentVal.includes('D:\\flutter\\bin')) {
    const updated = currentVal + ';D:\\flutter\\bin';
    cp.execSync(`setx PATH "${updated}"`, { encoding: 'utf8' });
    console.log('SUCCESS: Added D:\\flutter\\bin to User PATH.');
  } else if (currentVal.includes('D:\\flutter\\bin')) {
    console.log('ALREADY CONFIGURED: D:\\flutter\\bin in User PATH.');
  }
} catch (e) {
  console.log('Error updating PATH:', e.message);
}
