const fs = require('fs');
const path = require('path');

console.log('=== RUNNING STATIC AUDIT OF ALL DART FILES ===\n');

function getAllDartFiles(dir) {
  let results = [];
  const list = fs.readdirSync(dir);
  for (const file of list) {
    const full = path.join(dir, file);
    const stat = fs.statSync(full);
    if (stat && stat.isDirectory()) {
      results = results.concat(getAllDartFiles(full));
    } else if (file.endsWith('.dart')) {
      results.push(full);
    }
  }
  return results;
}

const libFiles = getAllDartFiles(path.join(__dirname, '..', 'lib'));
console.log(`Discovered ${libFiles.length} Dart files in lib/`);

const findings = {
  critical: [],
  high: [],
  medium: [],
  low: [],
  enhancement: []
};

for (const filePath of libFiles) {
  const relPath = path.relative(path.join(__dirname, '..'), filePath);
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');

  // Check file length (> 250 lines rule from AGENTS.md)
  if (lines.length > 250) {
    findings.low.push({
      file: relPath,
      rule: 'File Length Target (<= 250 lines)',
      detail: `File is ${lines.length} lines long.`
    });
  }

  // Check for TODOs / placeholders
  lines.forEach((line, idx) => {
    const trimmed = line.trim();
    if (/\bTODO\b/i.test(trimmed)) {
      findings.medium.push({
        file: relPath,
        line: idx + 1,
        rule: 'Unresolved TODO',
        detail: trimmed
      });
    }
    if (/placeholder/i.test(trimmed) && !trimmed.startsWith('//') && !trimmed.startsWith('*')) {
      findings.low.push({
        file: relPath,
        line: idx + 1,
        rule: 'Placeholder text',
        detail: trimmed
      });
    }
    // Check for empty catch blocks
    if (/catch\s*\([^\)]*\)\s*\{\s*\}/.test(trimmed)) {
      findings.high.push({
        file: relPath,
        line: idx + 1,
        rule: 'Silent empty catch block',
        detail: trimmed
      });
    }
    // Check for print statements in production code
    if (/\bprint\s*\(/.test(trimmed) && !relPath.includes('test')) {
      findings.low.push({
        file: relPath,
        line: idx + 1,
        rule: 'Direct print() call (prefer debugPrint or logger)',
        detail: trimmed
      });
    }
    // Check for hardcoded credentials / service_role
    if (/service_role|supabase_service_key/i.test(trimmed)) {
      findings.critical.push({
        file: relPath,
        line: idx + 1,
        rule: 'Potential service_role exposure',
        detail: trimmed
      });
    }
  });
}

console.log('AUDIT SUMMARY:');
console.log(`- Critical: ${findings.critical.length}`);
console.log(`- High: ${findings.high.length}`);
console.log(`- Medium: ${findings.medium.length}`);
console.log(`- Low: ${findings.low.length}`);
console.log(`- Enhancement: ${findings.enhancement.length}`);

if (findings.critical.length > 0) {
  console.log('\nCRITICAL FINDINGS:', JSON.stringify(findings.critical, null, 2));
}
if (findings.high.length > 0) {
  console.log('\nHIGH FINDINGS:', JSON.stringify(findings.high, null, 2));
}
if (findings.medium.length > 0) {
  console.log('\nMEDIUM FINDINGS:', JSON.stringify(findings.medium, null, 2));
}
if (findings.low.length > 0) {
  console.log('\nSAMPLE LOW FINDINGS (first 5):', JSON.stringify(findings.low.slice(0, 5), null, 2));
}
