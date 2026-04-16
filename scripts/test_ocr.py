#!/usr/bin/env python3
"""Test PaddleOCR API to examine response structure."""
import requests, json, time, sys, os

TOKEN = os.popen("defaults read SwiftLib SwiftLib.paddleOCRToken 2>/dev/null").read().strip()
JOB_URL = "https://paddleocr.aistudio-app.com/api/v2/ocr/jobs"
MODEL = "PaddleOCR-VL-1.5"
PDF_PATH = "/Users/water/Downloads/文献/水蚤对富营养化湖泊影响研究.pdf"
OUT_DIR = "/tmp/ocr_test"

os.makedirs(OUT_DIR, exist_ok=True)

# 1. Create job
print("Creating OCR job...")
with open(PDF_PATH, "rb") as f:
    files = {"file": (os.path.basename(PDF_PATH), f, "application/pdf")}
    data = {
        "model": MODEL,
        "optionalPayload": json.dumps({
            "useDocOrientationClassify": False,
            "useDocUnwarping": False,
            "useChartRecognition": True,
        })
    }
    resp = requests.post(JOB_URL, files=files, data=data,
                         headers={"Authorization": f"bearer {TOKEN}"}, timeout=60)

resp_json = resp.json()
print(f"Status: {resp.status_code}")
job_id = resp_json.get("data", {}).get("jobId")
print(f"Job ID: {job_id}")

if not job_id:
    print("Failed:", json.dumps(resp_json, indent=2, ensure_ascii=False))
    sys.exit(1)

# 2. Poll
print("Polling...")
while True:
    r = requests.get(f"{JOB_URL}/{job_id}",
                     headers={"Authorization": f"bearer {TOKEN}"}, timeout=30)
    d = r.json().get("data", {})
    state = d.get("state", "")
    print(f"  State: {state}")
    if state == "done":
        # Save full poll response
        with open(f"{OUT_DIR}/poll_response.json", "w") as f:
            json.dump(r.json(), f, indent=2, ensure_ascii=False)
        json_url = d.get("resultUrl", {}).get("jsonUrl", "")
        print(f"  JSON URL: {json_url[:80]}...")
        break
    elif state == "failed":
        print("Failed:", d.get("errorMsg"))
        sys.exit(1)
    time.sleep(3)

# 3. Fetch JSONL result
print("Fetching result...")
result_resp = requests.get(json_url, timeout=60)
raw_text = result_resp.text

# Save raw JSONL
with open(f"{OUT_DIR}/raw_result.jsonl", "w") as f:
    f.write(raw_text)

# Parse and save structured
lines = raw_text.strip().split("\n")
all_pages = []
for i, line in enumerate(lines):
    page_data = json.loads(line)
    all_pages.append(page_data)
    # Save each page separately for inspection
    with open(f"{OUT_DIR}/page_{i}.json", "w") as f:
        json.dump(page_data, f, indent=2, ensure_ascii=False)

# 4. Analyze structure
print(f"\n=== ANALYSIS: {len(lines)} pages ===\n")
for i, page in enumerate(all_pages):
    result = page.get("result", {})
    layouts = result.get("layoutParsingResults", [])
    print(f"--- Page {i} ---")
    print(f"  Top-level keys: {list(result.keys())}")

    for j, layout in enumerate(layouts):
        print(f"\n  Layout[{j}] keys: {list(layout.keys())}")
        if "markdown" in layout:
            md = layout["markdown"]
            print(f"    markdown keys: {list(md.keys())}")
            md_text = md.get("text", "")
            print(f"    markdown.text length: {len(md_text)}")
            print(f"    markdown.text preview: {md_text[:300]}...")
            if "images" in md:
                imgs = md["images"]
                print(f"    markdown.images: {len(imgs)} entries")
                for k in list(imgs.keys())[:3]:
                    print(f"      key: {k}, value length: {len(imgs[k])}")
        if "prunedResult" in layout:
            pr = layout["prunedResult"]
            print(f"    prunedResult keys: {list(pr.keys())}")
            if "layoutParsingResult" in pr:
                lpr = pr["layoutParsingResult"]
                print(f"    layoutParsingResult keys: {list(lpr.keys())}")
                # Check for tables, images, etc
                if "tables" in lpr:
                    tables = lpr["tables"]
                    print(f"    tables: {len(tables)} entries")
                    for t_idx, tbl in enumerate(tables[:2]):
                        print(f"      table[{t_idx}] keys: {list(tbl.keys())}")
                        if "markdown" in tbl:
                            print(f"        table markdown preview: {str(tbl['markdown'])[:200]}")
                if "images" in lpr:
                    images = lpr["images"]
                    print(f"    images: {len(images)} entries")
                    for im_idx, img in enumerate(images[:2]):
                        print(f"      image[{im_idx}] keys: {list(img.keys())}")
                if "layouts" in lpr:
                    lo = lpr["layouts"]
                    print(f"    layouts: {len(lo)} entries")
                    types = set(l.get("type", "") for l in lo)
                    print(f"    layout types: {types}")

print(f"\nFull results saved to {OUT_DIR}/")
