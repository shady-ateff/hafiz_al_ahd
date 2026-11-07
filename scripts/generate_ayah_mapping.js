/**
 * Quran Ayah Mapping Generator (Node.js)
 * Phase 1: High-Precision Deterministic Quran Ayah Mapping Engine
 * 
 * Maps every word, line, and page across the 604 pages of the Madani Mushaf
 * (QCFv2 layout) to its corresponding Surah, Ayah, location, and authentic Uthmani text.
 */

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
const DATA_DIR = path.join(ROOT_DIR, 'scripts', 'data');
const QPC2_DIR = path.join(DATA_DIR, 'qpc2_pages');
const APP_LINES_FILE = path.join(ROOT_DIR, 'assets', 'quran', 'mushaf', 'quran_lines.json');
const OUTPUT_FILE = path.join(ROOT_DIR, 'assets', 'quran', 'mushaf', 'ayah_mapping.json');

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

function generateMapping() {
  console.log('🚀 Starting Quran Ayah Mapping Generation...');

  // 1. Load existing app rendering lines for parity validation
  console.log('📱 Reading app quran_lines.json from:', APP_LINES_FILE);
  const appLinesData = JSON.parse(fs.readFileSync(APP_LINES_FILE, 'utf8'));

  // 2. Initialize Ayahs lookup map and word collector
  const ayahs = {};
  const ayahWordsCollector = {};

  for (let s = 1; s <= 114; s++) {
    const totalAyahs = VERSE_COUNTS[s - 1];
    for (let a = 1; a <= totalAyahs; a++) {
      const key = `${s}:${a}`;
      ayahs[key] = {
        surah: s,
        ayah: a,
        page: 0,
        end_page: 0,
        uthmani: '',
        words_count: 0,
        segments: []
      };
      ayahWordsCollector[key] = [];
    }
  }

  // 3. Process all 604 pages
  console.log('🔍 Processing and aligning 604 Mushaf pages...');
  const pages = {};
  let totalWords = 0;
  let totalQcfTokens = 0;
  let validatedLinesCount = 0;

  for (let p = 1; p <= 604; p++) {
    const pad = String(p).padStart(3, '0');
    const pageFilePath = path.join(QPC2_DIR, `page-${pad}.json`);
    const pageData = JSON.parse(fs.readFileSync(pageFilePath, 'utf8'));
    
    const textLines = pageData.lines.filter(l => l.type === 'text');
    const appPage = appLinesData[p - 1];
    const appLines = appPage.lines;

    if (textLines.length !== appLines.length) {
      throw new Error(`Page ${p} line count mismatch: qpc2 has ${textLines.length}, app has ${appLines.length}`);
    }

    const pageLines = [];

    for (let lineIdx = 0; lineIdx < textLines.length; lineIdx++) {
      const qpcLine = textLines[lineIdx];
      const appLine = appLines[lineIdx];

      const lineWords = [];
      const lineTokens = [];

      qpcLine.words.forEach((w, wIdx) => {
        totalWords++;
        const parts = w.location.split(':').map(Number);
        const s = parts[0];
        const a = parts[1];
        const wPos = parts[2];
        const aKey = `${s}:${a}`;
        const ayahObj = ayahs[aKey];

        if (!ayahObj) {
          throw new Error(`Unknown Ayah key: ${aKey} at page ${p} line ${qpcLine.line}`);
        }

        if (ayahObj.page === 0) {
          ayahObj.page = p;
        }
        ayahObj.end_page = p;
        ayahObj.words_count++;

        // Collect authentic Uthmani word (strip trailing ayah number digits if attached to end of ayah)
        const cleanUthmaniWord = w.word.replace(/\s*[\u0660-\u0669\d]+\s*$/, '').trim();
        if (cleanUthmaniWord.length > 0) {
          ayahWordsCollector[aKey].push({ wPos, word: cleanUthmaniWord });
        }

        // Update segments for highlighting / multi-line selection
        const segs = ayahObj.segments;
        if (segs.length > 0 && segs[segs.length - 1].page === p && segs[segs.length - 1].line === qpcLine.line) {
          segs[segs.length - 1].word_end = wIdx;
        } else {
          segs.push({
            page: p,
            line: qpcLine.line,
            word_start: wIdx,
            word_end: wIdx
          });
        }

        const qcfTokens = w.qpcV2.trim().split(/\s+/);
        lineTokens.push(...qcfTokens);
        totalQcfTokens += qcfTokens.length;

        lineWords.push({
          location: w.location,
          surah: s,
          ayah: a,
          word_index: wPos,
          uthmani: cleanUthmaniWord.length > 0 ? cleanUthmaniWord : w.word,
          qcf: w.qpcV2
        });
      });

      // Strict validation against appLine text
      const joinedLineQcf = lineWords.map(w => w.qcf).join(' ');
      if (joinedLineQcf !== appLine.text.trim()) {
        throw new Error(`Line parity mismatch at page ${p} line ${qpcLine.line}:\n  QPC: ${joinedLineQcf}\n  APP: ${appLine.text.trim()}`);
      }

      validatedLinesCount++;

      pageLines.push({
        line: qpcLine.line,
        surah: lineWords[0].surah,
        verse_range: qpcLine.verseRange || '',
        text: joinedLineQcf,
        words: lineWords
      });
    }

    pages[String(p)] = pageLines;
  }

  // 4. Assemble authentic Uthmani Ayah texts from sorted word tokens
  for (const [key, ayah] of Object.entries(ayahs)) {
    const collected = ayahWordsCollector[key];
    collected.sort((x, y) => x.wPos - y.wPos);
    ayah.uthmani = collected.map(x => x.word).join(' ');

    if (ayah.page === 0 || ayah.end_page === 0) {
      throw new Error(`Ayah ${key} was not mapped to any page!`);
    }
    if (ayah.segments.length === 0) {
      throw new Error(`Ayah ${key} has no segments!`);
    }
    if (!ayah.uthmani || ayah.uthmani.length === 0) {
      throw new Error(`Ayah ${key} is missing Uthmani text!`);
    }
  }

  const finalDataset = {
    metadata: {
      generated_at: new Date().toISOString(),
      narration: 'Hafs an Asim',
      mushaf_edition: 'King Fahd Complex Madani Mushaf V2 (15 Lines)',
      total_surahs: 114,
      total_ayahs: 6236,
      total_pages: 604,
      total_text_lines: validatedLinesCount,
      total_words: totalWords,
      total_qcf_tokens: totalQcfTokens
    },
    ayahs: ayahs,
    pages: pages
  };

  console.log('💾 Writing final mapping dataset to:', OUTPUT_FILE);
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(finalDataset));
  const fileSizeMb = (fs.statSync(OUTPUT_FILE).size / (1024 * 1024)).toFixed(2);

  console.log('✅ Mapping generated successfully!');
  console.log(`📊 Statistics:
  - Total Surahs: ${finalDataset.metadata.total_surahs}
  - Total Ayahs: ${finalDataset.metadata.total_ayahs}
  - Total Pages: ${finalDataset.metadata.total_pages}
  - Validated Lines: ${finalDataset.metadata.total_text_lines}
  - Total Words: ${finalDataset.metadata.total_words}
  - Total QCF Tokens: ${finalDataset.metadata.total_qcf_tokens}
  - File Size: ${fileSizeMb} MB
  `);
}

if (require.main === module) {
  try {
    generateMapping();
  } catch (err) {
    console.error('❌ Generation failed:', err);
    process.exit(1);
  }
}

module.exports = { generateMapping };
