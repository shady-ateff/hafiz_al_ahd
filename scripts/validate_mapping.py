"""
Quran Ayah Mapping Validator (Python)
Phase 1: Automated Validation Test Suite

Performs comprehensive end-to-end mathematical and textual integrity checks
on assets/quran/mushaf/ayah_mapping.json against canonical Quranic references.
"""

import os
import json
import re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
MAPPING_FILE = os.path.join(ROOT_DIR, 'assets', 'quran', 'mushaf', 'ayah_mapping.json')
APP_LINES_FILE = os.path.join(ROOT_DIR, 'assets', 'quran', 'mushaf', 'quran_lines.json')

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

def run_validation():
    print("🔍 Starting Comprehensive Quran Mapping Validation Suite...\n")

    if not os.path.exists(MAPPING_FILE):
        print("❌ ayah_mapping.json not found! Run generate_ayah_mapping first.")
        exit(1)

    with open(MAPPING_FILE, 'r', encoding='utf-8') as f:
        mapping_data = json.load(f)

    with open(APP_LINES_FILE, 'r', encoding='utf-8') as f:
        app_lines_data = json.load(f)

    ayahs = mapping_data['ayahs']
    pages = mapping_data['pages']

    surahs_found = set()
    ayahs_found = set()
    pages_found = set()
    duplicate_ayahs_count = 0
    missing_ayahs_count = 0
    unmatched_qcf_tokens_count = 0
    missing_uthmani_count = 0

    for key, ayah_obj in ayahs.items():
        if key in ayahs_found:
            duplicate_ayahs_count += 1
        ayahs_found.add(key)
        surahs_found.add(ayah_obj['surah'])

        if not ayah_obj.get('uthmani') or not ayah_obj['uthmani'].strip():
            missing_uthmani_count += 1

        if ayah_obj['page'] < 1 or ayah_obj['page'] > 604 or ayah_obj['end_page'] < 1 or ayah_obj['end_page'] > 604:
            print(f"Invalid page range for {key}: [{ayah_obj['page']}, {ayah_obj['end_page']}]")

    for s in range(1, 115):
        expected_verses = VERSE_COUNTS[s - 1]
        for a in range(1, expected_verses + 1):
            expected_key = f"{s}:{a}"
            if expected_key not in ayahs:
                missing_ayahs_count += 1
                print(f"Missing expected Ayah: {expected_key}")

    for p in range(1, 605):
        p_key = str(p)
        if p_key not in pages:
            print(f"Missing Page {p} in mapping pages!")
            continue
        pages_found.add(p)

        page_lines = pages[p_key]
        app_lines = app_lines_data[p - 1]['lines']

        if len(page_lines) != len(app_lines):
            unmatched_qcf_tokens_count += abs(len(page_lines) - len(app_lines))
            print(f"Page {p} line count mismatch: mapped={len(page_lines)}, app={len(app_lines)}")
            continue

        for l_idx in range(len(page_lines)):
            map_line = page_lines[l_idx]
            app_line = app_lines[l_idx]

            if map_line['text'] != app_line['text'].strip():
                unmatched_qcf_tokens_count += 1

            map_tokens = []
            for w in map_line['words']:
                map_tokens.extend(re.split(r'\s+', w['qcf'].strip()))

            app_tokens = re.split(r'\s+', app_line['text'].strip())

            if len(map_tokens) != len(app_tokens):
                unmatched_qcf_tokens_count += abs(len(map_tokens) - len(app_tokens))
            else:
                for t in range(len(map_tokens)):
                    if map_tokens[t] != app_tokens[t]:
                        unmatched_qcf_tokens_count += 1

    results = [
        {"check": "Surahs", "expected": 114, "actual": len(surahs_found), "status": "PASS" if len(surahs_found) == 114 else "FAIL"},
        {"check": "Ayahs", "expected": 6236, "actual": len(ayahs_found), "status": "PASS" if len(ayahs_found) == 6236 else "FAIL"},
        {"check": "Pages", "expected": 604, "actual": len(pages_found), "status": "PASS" if len(pages_found) == 604 else "FAIL"},
        {"check": "Missing Ayahs", "expected": 0, "actual": missing_ayahs_count, "status": "PASS" if missing_ayahs_count == 0 else "FAIL"},
        {"check": "Duplicate Ayahs", "expected": 0, "actual": duplicate_ayahs_count, "status": "PASS" if duplicate_ayahs_count == 0 else "FAIL"},
        {"check": "Unmatched QCF Tokens", "expected": 0, "actual": unmatched_qcf_tokens_count, "status": "PASS" if unmatched_qcf_tokens_count == 0 else "FAIL"},
        {"check": "Missing Uthmani Text", "expected": 0, "actual": missing_uthmani_count, "status": "PASS" if missing_uthmani_count == 0 else "FAIL"},
    ]

    print("| Check | Expected | Actual | Result |")
    print("|---|---|---|---|")
    for r in results:
        print(f"| {r['check']} | {r['expected']} | {r['actual']} | {r['status']} |")

    all_passed = all(r['status'] == 'PASS' for r in results)
    print("\n=======================================")
    if all_passed:
        print("🎉 ALL VALIDATION CHECKS PASSED (100% CANONICAL PARITY)")
    else:
        print("❌ SOME VALIDATION CHECKS FAILED!")
        exit(1)
    print("=======================================\n")

if __name__ == '__main__':
    run_validation()

