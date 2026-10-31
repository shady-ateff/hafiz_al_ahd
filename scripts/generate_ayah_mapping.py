"""
Quran Ayah Mapping Generator (Python)
Phase 1: High-Precision Deterministic Quran Ayah Mapping Engine

Maps every word, line, and page across the 604 pages of the Madani Mushaf
(QCFv2 layout) to its corresponding Surah, Ayah, location, and authentic Uthmani text.
"""

import os
import json
import re
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
DATA_DIR = os.path.join(SCRIPT_DIR, 'data')
QPC2_DIR = os.path.join(DATA_DIR, 'qpc2_pages')
APP_LINES_FILE = os.path.join(ROOT_DIR, 'assets', 'quran', 'mushaf', 'quran_lines.json')
OUTPUT_FILE = os.path.join(ROOT_DIR, 'assets', 'quran', 'mushaf', 'ayah_mapping.json')

VERSE_COUNTS = [
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
]

def generate_mapping():
    print("🚀 Starting Quran Ayah Mapping Generation...")

    print(f"📱 Reading app quran_lines.json from: {APP_LINES_FILE}")
    with open(APP_LINES_FILE, 'r', encoding='utf-8') as f:
        app_lines_data = json.load(f)

    ayahs = {}
    ayah_words_collector = {}
    for s in range(1, 115):
        total_ayahs = VERSE_COUNTS[s - 1]
        for a in range(1, total_ayahs + 1):
            key = f"{s}:{a}"
            ayahs[key] = {
                "surah": s,
                "ayah": a,
                "page": 0,
                "end_page": 0,
                "uthmani": "",
                "words_count": 0,
                "segments": []
            }
            ayah_words_collector[key] = []

    print("🔍 Processing and aligning 604 Mushaf pages...")
    pages = {}
    total_words = 0
    total_qcf_tokens = 0
    validated_lines_count = 0

    for p in range(1, 605):
        pad = f"{p:03d}"
        page_file_path = os.path.join(QPC2_DIR, f"page-{pad}.json")
        with open(page_file_path, 'r', encoding='utf-8') as f:
            page_data = json.load(f)

        text_lines = [l for l in page_data['lines'] if l.get('type') == 'text']
        app_page = app_lines_data[p - 1]
        app_lines = app_page['lines']

        if len(text_lines) != len(app_lines):
            raise ValueError(f"Page {p} line count mismatch: qpc2 has {len(text_lines)}, app has {len(app_lines)}")

        page_lines = []
        for line_idx in range(len(text_lines)):
            qpc_line = text_lines[line_idx]
            app_line = app_lines[line_idx]

            line_words = []
            for w_idx, w in enumerate(qpc_line['words']):
                total_words += 1
                s, a, w_pos = map(int, w['location'].split(':'))
                a_key = f"{s}:{a}"
                ayah_obj = ayahs[a_key]

                if ayah_obj['page'] == 0:
                    ayah_obj['page'] = p
                ayah_obj['end_page'] = p
                ayah_obj['words_count'] += 1

                clean_word = re.sub(r'\s*[\u0660-\u0669\d]+\s*$', '', w['word']).strip()
                if clean_word:
                    ayah_words_collector[a_key].append({'w_pos': w_pos, 'word': clean_word})

                segs = ayah_obj['segments']
                if segs and segs[-1]['page'] == p and segs[-1]['line'] == qpc_line['line']:
                    segs[-1]['word_end'] = w_idx
                else:
                    segs.append({
                        "page": p,
                        "line": qpc_line['line'],
                        "word_start": w_idx,
                        "word_end": w_idx
                    })

                qcf_tokens = re.split(r'\s+', w['qpcV2'].strip())
                total_qcf_tokens += len(qcf_tokens)

                line_words.append({
                    "location": w['location'],
                    "surah": s,
                    "ayah": a,
                    "word_index": w_pos,
                    "uthmani": clean_word if clean_word else w['word'],
                    "qcf": w['qpcV2']
                })

            joined_line_qcf = " ".join(w['qcf'] for w in line_words)
            if joined_line_qcf != app_line['text'].strip():
                raise ValueError(f"Line parity mismatch at page {p} line {qpc_line['line']}")

            validated_lines_count += 1
            page_lines.append({
                "line": qpc_line['line'],
                "surah": line_words[0]['surah'],
                "verse_range": qpc_line.get('verseRange', ''),
                "text": joined_line_qcf,
                "words": line_words
            })

        pages[str(p)] = page_lines

    for key, ayah in ayahs.items():
        collected = ayah_words_collector[key]
        collected.sort(key=lambda x: x['w_pos'])
        ayah['uthmani'] = " ".join(x['word'] for x in collected)

        if ayah['page'] == 0 or ayah['end_page'] == 0:
            raise ValueError(f"Ayah {key} was not mapped to any page!")
        if not ayah['segments']:
            raise ValueError(f"Ayah {key} has no segments!")
        if not ayah['uthmani']:
            raise ValueError(f"Ayah {key} is missing Uthmani text!")

    final_dataset = {
        "metadata": {
            "generated_at": datetime.utcnow().isoformat() + "Z",
            "narration": "Hafs an Asim",
            "mushaf_edition": "King Fahd Complex Madani Mushaf V2 (15 Lines)",
            "total_surahs": 114,
            "total_ayahs": 6236,
            "total_pages": 604,
            "total_text_lines": validated_lines_count,
            "total_words": total_words,
            "total_qcf_tokens": total_qcf_tokens
        },
        "ayahs": ayahs,
        "pages": pages
    }

    print(f"💾 Writing final mapping dataset to: {OUTPUT_FILE}")
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        json.dump(final_dataset, f, ensure_ascii=False, separators=(',', ':'))

    file_size_mb = os.path.getsize(OUTPUT_FILE) / (1024 * 1024)
    print("✅ Mapping generated successfully!")
    print(f"""📊 Statistics:
  - Total Surahs: {final_dataset['metadata']['total_surahs']}
  - Total Ayahs: {final_dataset['metadata']['total_ayahs']}
  - Total Pages: {final_dataset['metadata']['total_pages']}
  - Validated Lines: {final_dataset['metadata']['total_text_lines']}
  - Total Words: {final_dataset['metadata']['total_words']}
  - Total QCF Tokens: {final_dataset['metadata']['total_qcf_tokens']}
  - File Size: {file_size_mb:.2f} MB
    """)

if __name__ == '__main__':
    generate_mapping()
