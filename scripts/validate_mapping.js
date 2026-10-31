/**
 * Quran Ayah Mapping Validator (Node.js)
 * Phase 1: Automated Validation Test Suite
 * 
 * Performs comprehensive end-to-end mathematical and textual integrity checks
 * on assets/quran/mushaf/ayah_mapping.json against canonical Quranic references.
 */

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
const MAPPING_FILE = path.join(ROOT_DIR, 'assets', 'quran', 'mushaf', 'ayah_mapping.json');
const APP_LINES_FILE = path.join(ROOT_DIR, 'assets', 'quran', 'mushaf', 'quran_lines.json');

// Standard Hafs verse counts for each of the 114 Surahs
const VERSE_COUNTS = [
  7, 286, 200, 176, 120, 165, 206, 75, 129, 109,
  123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
  112, 78, 118, 64, 77, 227, 93, 88, 69, 60,
  34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
  54, 53, 89, 59, 37, 35, 38, 29, 18, 45,
  60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
  14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
  28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
  29, 19, 36, 25, 22, 17, 19, 26, 30, 20,
  15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
  11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
  5, 4, 5, 6
];

function runValidation() {
  console.log('🔍 Starting Comprehensive Quran Mapping Validation Suite...\n');

  if (!fs.existsSync(MAPPING_FILE)) {
    console.error('❌ ayah_mapping.json not found! Run generate_ayah_mapping.js first.');
    process.exit(1);
  }

  const mappingData = JSON.parse(fs.readFileSync(MAPPING_FILE, 'utf8'));
  const appLinesData = JSON.parse(fs.readFileSync(APP_LINES_FILE, 'utf8'));

  const ayahs = mappingData.ayahs;
  const pages = mappingData.pages;

  // Trackers
  const surahsFound = new Set();
  const ayahsFound = new Set();
  const pagesFound = new Set();
  let duplicateAyahsCount = 0;
  let missingAyahsCount = 0;
  let unmatchedQcfTokensCount = 0;
  let missingUthmaniCount = 0;

  // 1. Validate Ayahs Collection
  const ayahKeys = Object.keys(ayahs);
  for (const key of ayahKeys) {
    if (ayahsFound.has(key)) {
      duplicateAyahsCount++;
    }
    ayahsFound.add(key);

    const ayahObj = ayahs[key];
    surahsFound.add(ayahObj.surah);

    if (!ayahObj.uthmani || ayahObj.uthmani.trim().length === 0) {
      missingUthmaniCount++;
    }

    if (ayahObj.page < 1 || ayahObj.page > 604 || ayahObj.end_page < 1 || ayahObj.end_page > 604) {
      console.error(`Invalid page range for ${key}: [${ayahObj.page}, ${ayahObj.end_page}]`);
    }
  }

  // Check expected total verses across 114 surahs
  for (let s = 1; s <= 114; s++) {
    const expectedVerses = VERSE_COUNTS[s - 1];
    for (let a = 1; a <= expectedVerses; a++) {
      const expectedKey = `${s}:${a}`;
      if (!ayahs[expectedKey]) {
        missingAyahsCount++;
        console.error(`Missing expected Ayah: ${expectedKey}`);
      }
    }
  }

  // 2. Validate Pages & Token-by-Token Match with app's quran_lines.json
  let totalMappedTokens = 0;
  let totalAppTokens = 0;

  for (let p = 1; p <= 604; p++) {
    const pKey = String(p);
    if (!pages[pKey]) {
      console.error(`Missing Page ${p} in mapping pages!`);
      continue;
    }
    pagesFound.add(p);

    const pageLines = pages[pKey];
    const appLines = appLinesData[p - 1].lines;

    if (pageLines.length !== appLines.length) {
      unmatchedQcfTokensCount += Math.abs(pageLines.length - appLines.length);
      console.error(`Page ${p} line count mismatch: mapped=${pageLines.length}, app=${appLines.length}`);
      continue;
    }

    for (let l = 0; l < pageLines.length; l++) {
      const mapLine = pageLines[l];
      const appLine = appLines[l];

      // Compare raw line texts
      if (mapLine.text !== appLine.text.trim()) {
        unmatchedQcfTokensCount++;
        console.error(`Text mismatch on Page ${p} Line ${mapLine.line}`);
      }

      // Compare individual word glyph tokens
      const mapTokens = [];
      mapLine.words.forEach(w => {
        const parts = w.qcf.trim().split(/\s+/);
        mapTokens.push(...parts);
      });

      const appTokens = appLine.text.trim().split(/\s+/);

      totalMappedTokens += mapTokens.length;
      totalAppTokens += appTokens.length;

      if (mapTokens.length !== appTokens.length) {
        unmatchedQcfTokensCount += Math.abs(mapTokens.length - appTokens.length);
      } else {
        for (let t = 0; t < mapTokens.length; t++) {
          if (mapTokens[t] !== appTokens[t]) {
            unmatchedQcfTokensCount++;
          }
        }
      }
    }
  }

  // Build Results Table
  const results = [
    {
      check: 'Surahs',
      expected: 114,
      actual: surahsFound.size,
      status: surahsFound.size === 114 ? 'PASS' : 'FAIL'
    },
    {
      check: 'Ayahs',
      expected: 6236,
      actual: ayahsFound.size,
      status: ayahsFound.size === 6236 ? 'PASS' : 'FAIL'
    },
    {
      check: 'Pages',
      expected: 604,
      actual: pagesFound.size,
      status: pagesFound.size === 604 ? 'PASS' : 'FAIL'
    },
    {
      check: 'Missing Ayahs',
      expected: 0,
      actual: missingAyahsCount,
      status: missingAyahsCount === 0 ? 'PASS' : 'FAIL'
    },
    {
      check: 'Duplicate Ayahs',
      expected: 0,
      actual: duplicateAyahsCount,
      status: duplicateAyahsCount === 0 ? 'PASS' : 'FAIL'
    },
    {
      check: 'Unmatched QCF Tokens',
      expected: 0,
      actual: unmatchedQcfTokensCount,
      status: unmatchedQcfTokensCount === 0 ? 'PASS' : 'FAIL'
    },
    {
      check: 'Missing Uthmani Text',
      expected: 0,
      actual: missingUthmaniCount,
      status: missingUthmaniCount === 0 ? 'PASS' : 'FAIL'
    }
  ];

  console.log('| Check | Expected | Actual | Result |');
  console.log('|---|---|---|---|');
  results.forEach(r => {
    console.log(`| ${r.check} | ${r.expected} | ${r.actual} | ${r.status} |`);
  });

  const allPassed = results.every(r => r.status === 'PASS');
  console.log('\n=======================================');
  if (allPassed) {
    console.log('🎉 ALL VALIDATION CHECKS PASSED (100% CANONICAL PARITY)');
  } else {
    console.error('❌ SOME VALIDATION CHECKS FAILED!');
    process.exit(1);
  }
  console.log('=======================================\n');

  return { results, allPassed };
}

if (require.main === module) {
  runValidation();
}

module.exports = { runValidation };

